"""python -m unittest test_chat -v -- isolated SQLite, no production DB or messages."""
import unittest
from uuid import uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.chat_models import ChatMessage
from app.database import get_db
from app.models import Employee
from app.routers.chat import router
from app.security import create_access_token


class ChatTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread':False}, poolclass=StaticPool)
        Employee.__table__.create(self.engine)
        ChatMessage.__table__.create(self.engine)
        self.sessions = sessionmaker(bind=self.engine)
        with self.sessions() as db:
            for id, manager in [(1,False),(2,False),(10,True),(11,True)]:
                db.add(Employee(id=id,employee_code=f'T{id}',full_name=f'Test {id}',email=f't{id}@example.invalid',hashed_password='not-a-real-password',is_manager=manager))
            db.commit()
        app = FastAPI()
        app.include_router(router)
        def test_db():
            with self.sessions() as db: yield db
        app.dependency_overrides[get_db] = test_db
        self.client = TestClient(app)

    def tearDown(self):
        self.client.close()
        self.engine.dispose()

    def headers(self, id):
        return {'Authorization': f'Bearer {create_access_token(f"T{id}")}'}

    def send(self, sender=1, recipient=10, body='สวัสดี', key=None):
        return self.client.post(f'/chat/messages/{recipient}',headers=self.headers(sender),json={'body':body,'client_id':key or str(uuid4())})

    def get(self, sender, path):
        return self.client.get(path,headers=self.headers(sender))

    def test_auth_required(self):
        self.assertEqual(self.client.get('/chat/contacts').status_code,401)
        self.assertEqual(self.client.post('/chat/messages/10',json={'body':'x','client_id':str(uuid4())}).status_code,401)
        self.assertEqual(self.client.get('/chat/messages/10',headers={'Authorization':'Bearer invalid'}).status_code,401)

    def test_contacts_only_opposite_role_and_minimal_profile(self):
        rows=self.get(1,'/chat/contacts').json()['contacts']
        self.assertEqual({x['id'] for x in rows},{10,11})
        self.assertEqual({x['id'] for x in self.get(10,'/chat/contacts').json()['contacts']},{1,2})
        self.assertNotIn('email',rows[0]); self.assertNotIn('hashed_password',rows[0])

    def test_messages_private_and_bidirectional(self):
        self.assertEqual(self.send().status_code,200)
        self.assertEqual(self.send(10,1,'รับทราบ').status_code,200)
        self.assertEqual(len(self.get(1,'/chat/messages/10').json()['messages']),2)
        self.assertEqual(len(self.get(10,'/chat/messages/1').json()['messages']),2)
        self.assertEqual(self.get(2,'/chat/messages/10').json()['messages'],[])
        self.assertEqual(self.get(11,'/chat/messages/1').json()['messages'],[])
        self.assertEqual(self.get(2,'/chat/contacts').json()['contacts'][0]['last_message'],None)

    def test_self_and_same_role_are_forbidden_on_every_endpoint(self):
        for sender,recipient in [(1,1),(1,2),(10,11)]:
            self.assertEqual(self.send(sender,recipient).status_code,403)
            self.assertEqual(self.get(sender,f'/chat/messages/{recipient}').status_code,403)
            self.assertEqual(self.client.post(f'/chat/read/{recipient}',headers=self.headers(sender),json={'through_id':1}).status_code,403)
        self.assertEqual(self.send(1,999).status_code,404)

    def test_read_receipts_unread_and_boundaries(self):
        a=self.send(body='one').json(); b=self.send(body='two').json()
        contact=next(x for x in self.get(10,'/chat/contacts').json()['contacts'] if x['id']==1)
        self.assertEqual(contact['unread_count'],2)
        self.assertEqual(contact['last_message']['body'],'two')
        self.assertEqual(self.client.post('/chat/read/1',headers=self.headers(10),json={'through_id':a['id']}).status_code,200)
        data=self.get(1,'/chat/messages/10').json()
        self.assertEqual(data['peer_read_through_id'],a['id'])
        self.assertIsNotNone(data['messages'][0]['read_at']); self.assertIsNone(data['messages'][1]['read_at'])
        # Another employee cannot mark this pair's messages read.
        self.assertEqual(self.client.post('/chat/read/10',headers=self.headers(2),json={'through_id':b['id']}).status_code,404)

    def test_idempotent_retries_and_conflicting_key(self):
        key=str(uuid4())
        a=self.send(key=key).json(); b=self.send(key=key).json()
        self.assertEqual(a['id'],b['id'])
        self.assertEqual(self.send(body='changed',key=key).status_code,409)
        self.assertEqual(self.send(recipient=11,key=key).status_code,409)
        self.assertEqual(len(self.get(1,'/chat/messages/10').json()['messages']),1)

    def test_validation_and_sender_cannot_be_spoofed(self):
        for body in ['', ' \n ', 'x'*2001]: self.assertEqual(self.send(body=body).status_code,422)
        self.assertEqual(self.send(key='bad-id').status_code,422)
        self.assertEqual(len(self.send(body='x'*2000).json()['body']),2000)
        result=self.client.post('/chat/messages/10',headers=self.headers(1),json={'body':'  hello\nworld  ','client_id':str(uuid4()),'sender_id':2}).json()
        self.assertEqual(result['sender_id'],1); self.assertEqual(result['body'],'hello\nworld')
        self.assertTrue(result['created_at'].endswith('+00:00'))

    def test_pagination_no_gaps_and_no_cross_pair_leakage(self):
        ids=[self.send(body=str(i)).json()['id'] for i in range(7)]
        self.send(2,10,'secret-other-conversation')
        first=self.get(1,'/chat/messages/10?limit=3').json()
        self.assertEqual([x['id'] for x in first['messages']],ids[-3:]); self.assertTrue(first['has_more'])
        older=self.get(1,f'/chat/messages/10?limit=3&before_id={ids[-3]}').json()
        self.assertEqual([x['id'] for x in older['messages']],ids[1:4])
        after=self.get(1,f'/chat/messages/10?limit=3&after_id={ids[1]}').json()
        self.assertEqual([x['id'] for x in after['messages']],ids[2:5])
        self.assertEqual(self.get(1,'/chat/messages/10?before_id=3&after_id=1').status_code,422)
        self.assertEqual(self.get(1,'/chat/messages/10?limit=101').status_code,422)

    def test_private_responses_are_not_cached(self):
        for response in [self.get(1,'/chat/contacts'),self.get(1,'/chat/messages/10'),self.send()]:
            self.assertEqual(response.headers['cache-control'],'no-store')


if __name__ == '__main__': unittest.main()
