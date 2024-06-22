"""Example 1 - Simple Compilation with Csound

This example is a barebones example for creating an instance of Csound, 
compiling a pre-existing CSD, calling Perform to run Csound to completion,
then Stop and exit.  
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import csnd


def test_compile():
    c = csnd.Csound()
    c.compile("dummy", "test1.csd")
    c.perform()
    c.stop()
 

