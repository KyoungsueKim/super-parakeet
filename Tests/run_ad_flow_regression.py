from pathlib import Path
import shutil, subprocess, tempfile
repo = Path(__file__).resolve().parents[1]
tests = Path(__file__).parent / 'AdFlow'
with tempfile.TemporaryDirectory(prefix='super-parakeet-auto-flow-') as tmp:
    work = Path(tmp)
    shutil.copyfile(repo/'super-parakeet/Service/AdLifecycle.swift',work/'AdLifecycle.swift')
    source = (repo/'super-parakeet/Service/RewardedAdFlowCoordinator.swift').read_text()
    (work/'Coordinator.swift').write_text(source.replace('import UIKit\n',''))
    for name in ['UIKitMocks.swift','main.swift']: shutil.copyfile(tests/name,work/name)
    subprocess.run(['xcrun','swiftc','-swift-version','5','-module-cache-path',str(work/'modules'),str(work/'AdLifecycle.swift'),str(work/'UIKitMocks.swift'),str(work/'Coordinator.swift'),str(work/'main.swift'),'-o',str(work/'regression')],check=True)
    subprocess.run([str(work/'regression')],check=True)
