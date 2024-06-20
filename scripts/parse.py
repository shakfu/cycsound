import re
import textwrap

FUNC_PATTERN = re.compile(r"cdef ([\w\.]+) (\w+)\((.+)\)")

def camel_to_snake(name):
    name = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', name)
    return re.sub('([a-z0-9])([A-Z])', r'\1_\2', name).lower()

def list_to_pairs(lst):
   return list(zip(lst[::2], lst[1::2]))


class Function:
   def __init__(self, rtype, name, args):
      self.rtype = rtype
      self.name = name
      self.args = args
      self.doc = ''

   @classmethod
   def from_fun(cls, fun):
      m = FUNC_PATTERN.match(fun)
      if m:
         return cls(*m.groups())
      raise TypeError(f"could not parse func: '{fun}'")

   @property
   def method(self):
      return camel_to_snake(self.name.lstrip('csound'))

   def display(self):
      rtype = '' if self.rtype == 'void' else self.rtype
      print(f"cdef {rtype} {self.method}({self.args}):")
      print(textwrap.indent('"""'+doc, ' '*4))   
      print('    """')
      if not rtype:
         print(f"    cs.{self.name}( )")         
      else:
         print(f"    return cs.{self.name}( )")
      # if not rtype:
      #    print(f"    cs.{self.name}(self.ptr, )")         
      # else:
      #    print(f"    return cs.{self.name}(self.ptr, )")
      print()


with open('demo.pyx') as f:
   txt = f.read()

lines = [i.strip() for i in txt.split('"""')]

lines = [line for line in lines if line]

pairs = list_to_pairs(lines)

for doc, fun in pairs:
   try:
      f = Function.from_fun(fun)
      f.doc = doc
      f.display()
   except TypeError:
      print("ERROR: ", fun)


# for doc, fun in pairs:
#    print(fun)
#    print(textwrap.indent('"""'+doc, ' '*4))
#    print('    """')
#    print()

