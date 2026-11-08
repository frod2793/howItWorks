#!/usr/bin/env python3
"""Run the real validator against a weakened schema; no Unity execution."""
from pathlib import Path
import shutil, subprocess, tempfile, unittest

AGENTS = Path(__file__).resolve().parents[1]

class CoverageGateTests(unittest.TestCase):
    def test_schema_cannot_relax_coverage_gate(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            for relative in ('scripts/validation/check-unity-milestone.sh','scripts/shared/profile.sh','config/unity-milestone-validation-schema.conf'):
                target=root/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(AGENTS/relative,target)
            evidence=root/'evidence.conf';original=(AGENTS/'config/unity-milestone-validation.example.conf').read_text()
            schema=root/'config/unity-milestone-validation-schema.conf';original_schema=schema.read_text()
            for name,coverage,line,success in (
                ('confirmed','coverage_status=confirmed','coverage_status|required|single|enum|confirmed',True),
                ('weakened-enum','coverage_status=unconfirmed','coverage_status|required|single|enum|confirmed,unconfirmed',False),
                ('optional-missing','','coverage_status|optional|single|text|',False),
                ('duplicate','coverage_status=confirmed\ncoverage_status=confirmed','coverage_status|required|multiple|text|',False),
            ):
                with self.subTest(name=name):
                    schema.write_text(original_schema.replace('coverage_status|required|single|enum|confirmed',line))
                    evidence.write_text(original.replace('coverage_status=confirmed',coverage))
                    result=subprocess.run(['bash',str(root/'scripts/validation/check-unity-milestone.sh'),'--evidence',str(evidence),'--phase','prebuild','--change-id','commit-abc123'],capture_output=True,text=True)
                    print(name,'exit',result.returncode,(result.stderr or result.stdout).strip())
                    self.assertEqual(result.returncode==0,success)

if __name__=='__main__':unittest.main()
