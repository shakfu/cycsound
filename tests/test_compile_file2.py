"""More complex csd playing example


"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))



import csnd

def test_compile():
    c = csnd.Csound()
    c.compile("dummy", "diskgrain.csd")
    c.perform()
    c.stop()
 

