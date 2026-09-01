FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*

# requirements.txt อ้าง -r requirements-base.txt ต่อ จึงต้อง copy มาทั้งชุด
# (ถ้า copy แค่ requirements.txt จะพังตอน pip: "No such file: requirements-base.txt")
COPY requirements*.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
