"""Run the real Recall walker in a disposable graph and retain only its result."""
from pathlib import Path
from tempfile import TemporaryDirectory
import hashlib
import json
import shutil
import subprocess
import sys
ROOT=Path(__file__).resolve().parent
files=("public_recall_demo.jac","read.jac","graph.jac")
with TemporaryDirectory(prefix="alongside-public-recall-") as directory:
    temp=Path(directory)
    for name in files:shutil.copy2(ROOT/name,temp/name)
    run=subprocess.run(["jac","run","public_recall_demo.jac"],cwd=temp,capture_output=True,text=True,check=True)
    result=json.loads(next(line for line in run.stdout.splitlines() if line.startswith("{")))
    assert result["allowed"] is False and len(result["violations"])==1
    result["source"]={"repository":"https://github.com/nathansso/Alongside","revision":subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),"walker":"read.jac","walker_sha256":hashlib.sha256((ROOT/"read.jac").read_bytes()).hexdigest(),"sha256":{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in files},"command":"python3 export_public_recall.py OUTPUT.json","runtime":subprocess.check_output(["jac","--version"],text=True).strip(),"isolation":"Fresh temporary directory and graph per invocation; removed after result capture"}
    out=Path(sys.argv[1]);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+"\n")
    print("Original Recall rejected the fictional addition with exactly one cited constraint; temporary graph removed")
