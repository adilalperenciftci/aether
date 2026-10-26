#!/usr/bin/env python3
"""Unit tests for check_platform_env.py (#3119): each spelling of the read is
flagged and the build's answer is not, so a rule change here is a red test
rather than a green `make check-tests` that quietly stopped seeing one.

Run from anywhere: `python3 tests/scripts/test_check_platform_env.py`.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_platform_env as cpe  # noqa: E402


class PlatformFromEnvTest(unittest.TestCase):
    def test_each_spelling_is_flagged(self):
        src = ('main() {\n'
               '    a = os.getenv("OS") == "Windows_NT"\n'
               '    b = os_getenv("OS")\n'
               '    c = getenv( "OS" )\n'
               '}\n')
        self.assertEqual(cpe.check_source(src), [2, 3, 4])

    def test_the_build_answer_is_clean(self):
        src = 'main() {\n    w = os.platform() == "windows"\n}\n'
        self.assertEqual(cpe.check_source(src), [])

    def test_a_comment_is_not_a_read(self):
        src = 'main() {\n    // was os.getenv("OS") == "Windows_NT"\n}\n'
        self.assertEqual(cpe.check_source(src), [])

    def test_another_variable_is_clean(self):
        src = 'main() {\n    h = os.getenv("OSTYPE")\n    p = os.getenv("PATH")\n}\n'
        self.assertEqual(cpe.check_source(src), [])


class ShellPlatformFromEnvTest(unittest.TestCase):
    def test_the_environments_os_is_flagged(self):
        src = ('set -e\n'
               'if [ "$OS" = "Windows_NT" ]; then\n'
               '    exit 0\n'
               'fi\n'
               'case "${OS:-}" in Windows_NT) EXE=.exe ;; esac\n')
        self.assertEqual(cpe.check_shell_source(src), [2, 5])

    def test_uname_is_clean(self):
        src = 'case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Windows_NT) EXE=.exe ;; esac\n'
        self.assertEqual(cpe.check_shell_source(src), [])

    def test_a_script_that_sets_its_own_os_is_clean(self):
        src = 'OS="$(uname -s 2>/dev/null)"\nif [ "$OS" = Linux ]; then :; fi\n'
        self.assertEqual(cpe.check_shell_source(src), [])
        src = 'ARCH="$(uname -m)"; OS="$(uname -s)"\ncase "$OS-$ARCH" in *) ;; esac\n'
        self.assertEqual(cpe.check_shell_source(src), [])

    def test_a_comment_and_another_variable_are_clean(self):
        src = '# was [ "$OS" = "Windows_NT" ]\necho "$OSTYPE" "${OSX_SDK:-}"\n'
        self.assertEqual(cpe.check_shell_source(src), [])


if __name__ == '__main__':
    unittest.main()
