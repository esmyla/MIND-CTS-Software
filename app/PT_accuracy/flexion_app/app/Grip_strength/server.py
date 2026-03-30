from fastapi import FastAPI
import subprocess
app = FastAPI()

@app.get("/start-session")
def start_session():
    try:
        result = subprocess.run(["python", "grip_s.py"], capture_output=True, text=True)
        max_grip = None
        for line in result.stdout.splitlines():
            if line.startswith("Max_grip"):
                max_grip = int(line.split("=")[1])
        return {"status": "success",
                "max_grip": max_grip,
                "raw_data": result.stdout,
                "output": result.stdout}
    except Exception as e:
        return {"status": "error", "output": str(e)}