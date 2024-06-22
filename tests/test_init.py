import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import cycsound


def test_csound():
	c = cycsound.Csound()

