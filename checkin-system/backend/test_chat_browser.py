"""Run browser tests against the real chat router with an isolated, disposable database."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'backend'))
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import uvicorn
from app.models import Employee
from app.chat_models import ChatMessage
from app.database import get_db
from app.routers.chat import router
from app.security import create_access_token

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='checkin-chat-browser-') as temp:
        engine = create_engine('sqlite:///' + str(Path(temp) / 'test.db'), connect_args={'check_same_thread':False})
        Employee.__table__.create(engine); ChatMessage.__table__.create(engine)
        sessions = sessionmaker(bind=engine)
        users = [dict(id=1, employee_code='TEST1', full_name='พนักงานทดสอบ', email='one@example.invalid', is_manager=False),
                 dict(id=2, employee_code='TEST2', full_name='พนักงานอีกคน', email='two@example.invalid', is_manager=False),
                 dict(id=10, employee_code='BOSS10', full_name='หัวหน้าทดสอบ', email='boss@example.invalid', is_manager=True)]
        with sessions() as db:
            for user in users: db.add(Employee(**user, hashed_password='test-only'))
            db.commit()
        app = FastAPI()
        def test_db():
            with sessions() as db: yield db
        app.dependency_overrides[get_db] = test_db
        app.include_router(router)
        @app.get('/__test/session/{id}')
        def session(id:int):
            user = next(user for user in users if user['id']==id)
            return {'employee':user, 'token':create_access_token(user['employee_code'])}
        @app.get('/reports/geofence')
        def geofence():
            return {'offices':[{'name':'Motta & Montipa (Head office)','lat':13.9040518,'lng':100.5391995,'radius_km':.5}],
                'work_schedule':{'work_start':'08:30','work_end':'17:30','enabled':True,'late_grace_minutes':0,'early_leave_grace_minutes':0}}
        @app.get('/checkins/me')
        @app.get('/faces/me')
        def empty(): return []
        @app.get('/app/info')
        def info(): return {'available':False}
        @app.get('/reports/team-calendar')
        def calendar(): return {'days':[]}
        @app.get('/face-records')
        def spa(): return FileResponse(root / 'frontend/dist/index.html')
        app.mount('/', StaticFiles(directory=root / 'frontend/dist', html=True), name='static')
        sock=socket.socket(); sock.bind(('127.0.0.1',0))
        server=uvicorn.Server(uvicorn.Config(app, log_level='error'))
        thread=threading.Thread(target=lambda:server.run(sockets=[sock]),daemon=True); thread.start()
        for _ in range(100):
            if server.started: break
            time.sleep(.05)
        env={**os.environ,'CHAT_TEST_ORIGIN':f'http://127.0.0.1:{sock.getsockname()[1]}', 'CHAT_TEST_ARTIFACTS':temp}
        try:
            result=subprocess.run(['node', str(root / 'frontend/tests/chat-browser.cjs')],env=env)
        finally:
            server.should_exit=True; thread.join(5); engine.dispose()
        sys.exit(result.returncode)
