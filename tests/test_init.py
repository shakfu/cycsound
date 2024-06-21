import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import csnd


def test_csound():
	c = csnd.Csound()

