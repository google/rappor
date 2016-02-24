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

def printDelta(x):
  printDelta(x[1], x[0], x[2])

def printDelta(f, p, q):
  for i in range(2,10):
    p_id = pid(i,f,p,q)
    p_other = pother(i,f,p,q)
    print(i, p_id, ' vs ', p_other, ' delta ', p_id-p_other, ' for a sum of ', predictN(max(p_id,p_other), p_id-p_other))

def eInf(f, h):
  if f <= 1.0:
    return 2 * h * log( (1-.5*f)/(.5*f) ) / log(2)
  else:
    return 2 * h * log( (.5*f)/(1-.5*f) ) / log(2)

def getData():
  for h in (1,2):
    for f in (.125,.2,.25,.3,.4,.5,.75,1,1.25,1.5,1.75) :
      for p in (.0,.1,.2,.3,.4,.5,.6,.7,.8,.9) :
        for q in (.15,.25,.35,.45,.55,.65,.75,.85,1) :
          yield (f, p, q, h, 1/(.5*f), eInf(f,h), signal(f, p, q, h), valueIFPQ(2,f,p,q), valueIFPQ(3,f,p,q), valueIFPQ(10000,f,p,q))

def toColor(color):
  x = max(1, min(255, int(round(color * 256.0))))
  return hex(x*256*256 + x*256 + x)[2:]

def makePlot():
  fig = plt.figure()
  ax = fig.add_subplot(111, projection='3d')
  for f, p, q, h, s, e, sig, val2, val3, val10000 in getData():
    ax.scatter(e, log(val10000)/log(2), log(sig)/log(2), s=(h*h*10), c=(0.5*f,p,q), marker='o')
  ax.set_xlabel('e \n Epsilon of privacy bound')
  ax.set_ylabel('log(val10000) \n Log of number of bits of K needed to form a identifier that could distinguish two users')
  ax.set_zlabel('log(sig) \n The log scale of the amount of data gained per repport. \n (The inverse of the number of repports needed to distinguish something from nothing)')
  ax.text(0,9,1.5,"Good")
  ax.text(12,-1,-9,"Bad")
  plt.show()

makePlot()