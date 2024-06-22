"""More complex csd playing example


"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))



import cycsound

def test_compile():
    c = cycsound.Csound()
    c.compile("dummy", "diskgrain.csd")
    c.perform()
    c.stop()
 

