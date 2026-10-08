#!/usr/bin/env python3
"""Compile production queue/provider/session/VM/use-case code against macOS SDK.
Network SDK client is excluded and replaced with a client that cannot send requests.
All PDFs, manifests, and compiler outputs live in a unique temporary workspace.
"""
import os
from pathlib import Path
import subprocess
import shutil
import tempfile

repo = Path(__file__).resolve().parents[1]
# Allow running staged tests before installation.
if (repo / 'PrintJobs.swift').exists():
    queue = repo / 'PrintJobs.swift'; requests = repo / 'Requests.swift'; vm = repo / 'UploadStatusViewModel.swift'
    extensions = Path('/Volumes/projects/XcodeProjects/super-parakeet/super-parakeet/Configuration/Extensions.swift')
else:
    queue = repo / 'super-parakeet/Model/PrintJobs.swift'
    requests = repo / 'super-parakeet/Service/Requests.swift'
    vm = repo / 'super-parakeet/ViewModel/UploadStatusViewModel.swift'
    extensions = repo / 'super-parakeet/Configuration/Extensions.swift'
with tempfile.TemporaryDirectory(prefix='super-parakeet-regression-') as tmp:
    work = Path(tmp)
    request_text = requests.read_text()
    pure = request_text[:request_text.index('/// Alamofire 기반 업로드 클라이언트.')]
    pure += request_text[request_text.index('/// 여러 문서를 업로드하고 진행 상태를 제공하는 유즈케이스.'):]
    pure = pure.replace('import Alamofire', 'struct AFError: Error {}')
    pure += '\nfinal class AlamofireUploadClient: UploadRequesting { func upload(job: UploadJob, phoneNumber: String) async throws { fatalError("Network forbidden in regression suite") } }\n'
    pure += '\nenum ModalViewState { case PROGRESS, SUCCESS, FAILED }\n'
    (work/'UploadCore.swift').write_text(pure)
    for source, name in [(queue,'PrintJobs.swift'),(extensions,'Extensions.swift'),(vm,'UploadStatusViewModel.swift')]:
        shutil.copyfile(source, work/name)
    queue=work/'PrintJobs.swift'; extensions=work/'Extensions.swift'; vm=work/'UploadStatusViewModel.swift'
    (work/'main.swift').write_text((Path(__file__).parent/'PDFImportRegression.swift').read_text())
    binary = work/'regression'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-module-cache-path','/tmp/super-parakeet-import-audit/module-cache',str(queue),str(extensions),str(vm),str(work/'UploadCore.swift'),str(work/'main.swift'),'-o',str(binary)],check=True)
    env=os.environ.copy(); env['PDF_TEST_ROOT']=str(work/'fixtures'); (work/'fixtures').mkdir()
    subprocess.run([str(binary)],env=env,check=True)
