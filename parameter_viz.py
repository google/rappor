from numpy import arange
from numpy import log

from mpl_toolkits.mplot3d import Axes3D
import matplotlib.pyplot as plt


def pid(x, f, p, q):
  return .5*f*(q**x + (1-q)**x) + (1-.5*f)*((1-p)**x + p**x)

def pother(x, f, p, q):
  b = .5 * f * q + (1-.5*f) * p
  return ( .5*f*(q*b + (1-q)*(1-b)) + (1-.5*f)*(p*b**(x-1) + (1-p)*(1-b)**(x-1)) )


def delta(x, f, p, q):
  return pid(x,f,p,q) - pother(x,f,p,q)

def predictN(prob, delta):
  if delta == 0:
    return float('inf')
  return prob * (1-prob) * 4 / (delta**2)

def valueFPQ(f, p, q):
  total = 0
  for i in range(2,4):
    total += valueIFPQ(i,f,p,q)
  return total

def valueIFPQ(i,f,p,q):
  p_id = pid(i, f, p, q)
  p_other = pother(i,f,p,q)
  return predictN(max(p_id, p_other), abs(p_id - p_other))

def signal(f, p, q, h):
  pStar = .5 * f * q + (1-.5*f) * p # Probability of a bit being 1 from a true value of 0 in the irr
  qStar = (1-.5*f) * q + .5 * f * p
  if p == q:
    return 0
  elif pStar < qStar:
    return 1.0 / predictN(pStar**h, (qStar**h-pStar**h))
  else:
    return 1.0 / predictN((1-pStar)**h, (1-qStar)**h - (1-pStar)**h)

def value(x) :  
  return - signal(x[0],x[1],x[2], 1) * valueFPQ(x[0], x[1], x[2], 1)

def printDelta(x):
  printDelta(x[1], x[0], x[2])

def printDelta(f, p, q):
  for i in range(2,10):
    p_id = pid(i,f,p,q)
    p_other = pother(i,f,p,q)
    print(i, p_id, ' vs ', p_other, ' delta ', p_id-p_other, ' for a sum of ', predictN(max(p_id,p_other), p_id-p_other))

def eInf(f, h):
  return 2 * h * log( (1-.5*f)/(.5*f) )

def getData():
  for h in (1,2):
    for f in (.125,.25,.5,.75) :
      for p in (.0,.1,.25,.4,.5,.6,.75,.9,1) :
        for q in (.0,.1,.25,.5,.75,.9,1) :
          if abs(p-q) > 0.05 :
            yield (f, p, q, h, 1/(.5*f), eInf(f,h), signal(f, p, q, h), valueIFPQ(2,f,p,q), valueIFPQ(3,f,p,q), valueIFPQ(10000,f,p,q))

def toColor(color):
  x = max(1, min(255, int(round(color * 256.0))))
  return hex(x*256*256 + x*256 + x)[2:]

def makePlot():
  fig = plt.figure()
  ax = fig.add_subplot(111, projection='3d')
  for f, p, q, h, s, e, sig, val2, val3, val1000 in getData():
    ax.scatter(e, log(val1000), log(sig), s=(h*h*10), c='%s'%f, marker='o')
  ax.set_xlabel('e')
  ax.set_ylabel('log(val1000)')
  ax.set_zlabel('log(sig)')
  plt.show()

makePlot()