from numpy import arange
from numpy import log
from numpy import linspace
from numpy import floor

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

def signal(f, p, q, h, k):
  pStar = .5 * f * q + (1-.5*f) * p # Probability of a bit being 1 from a true value of 0 in the irr
  qStar = (1-.5*f) * q + .5 * f * p # Probability of a bit being 0 from a true value of 1 in the irr
  if k <= 1:
    return 0
  probCollision = (1.0 * h) / k
  qPrime = qStar*(1-probCollision) + (probCollision*pStar)
  if pStar == qPrime:
    return 0
  elif pStar < qPrime:
    return 1.0 / predictN(pStar**h, qPrime**h - pStar**h)
  else:
    return 1.0 / predictN((1-pStar)**h, (1-qPrime)**h - (1-pStar)**h)

def printDelta(x):
  printDelta(x[1], x[0], x[2])

def printDelta(f, p, q):
  for i in range(2,10):
    p_id = pid(i,f,p,q)
    p_other = pother(i,f,p,q)
    print(i, p_id, ' vs ', p_other, ' delta ', p_id-p_other, ' for a sum of ', predictN(max(p_id,p_other), p_id-p_other))

def toPow2(x):
  if x<=1:
    return 0
  return 2**floor(log(x)/log(2))

def eInf(f, h):
  if f <= 1.0:
    return 2 * h * log( (1-.5*f)/(.5*f) ) / log(2)
  else:
    return 2 * h * log( (.5*f)/(1-.5*f) ) / log(2)

def getData():
  for h in (1, 2):
    for f in (.125,.2,.25,.3,.4,.5,.75,1,1.25,1.5,1.75) :
      for p in (.0,.1,.2,.3,.4,.5,.6,.7,.8,.9) :
        for q in (.15,.25,.35,.45,.55,.65,.75,.85,1) :
          maxk = toPow2(valueIFPQ(2,f,p,q))
          sig = signal(f, p, q, h, maxk)
          e = eInf(f,h)
          if sig > 0 and e < 10:
            yield (f, p, q, h, maxk, e, 1/sig, valueIFPQ(2,f,p,q), valueIFPQ(10000,f,p,q))

def toColor(color):
  x = max(1, min(255, int(round(color * 256.0))))
  return hex(x*256*256 + x*256 + x)[2:]

def makePlot(pointGenerator):
  fig = plt.figure()
  ax = fig.add_subplot(111, projection='3d')
  for f, p, q, h, maxk, e, detThres, val2, val10000 in pointGenerator():
    ax.scatter(e, log(val10000)/log(2), log(detThres)/log(2), s=h*20, c=(0.5*f,p,q), marker='o')
  ax.view_init(elev=20.,azim=45)
  ax.invert_zaxis()
  ax.set_xlabel('e \n Epsilon of privacy bound')
  ax.set_ylabel('log(val10000) \n Log of number of bits of K needed to form a identifier that could distinguish two users')
  ax.set_zlabel('Detectability theashold \n The log base 2 of the number of repports needed to detect a value')
  ax.text(1,10,0,"Good")
  ax.text(9,-2,12,"Bad")
  plt.show()


def value(f, h, k, p, q):
  maxk = floor(valueIFPQ(2,f,p,q))
  if maxk < k:
    return -maxk
  return signal(f, p, q, h, k)


def getOptimalPQ():
  for f in (.125,.2,.25,.3,.4,.5,.75):
    for h in (1,2):
      if h>1 and f<.4:
        continue
      for k in (8,32,64,126,256):
        bestScore = value(f,h,k,.25,.75)
        for p in linspace(0.0,1.0,101):
          for q in linspace(0.0,1.0,101):
            score = value(f,h,k,p,q)
            if score > bestScore:
              bestScore = score
        for p in linspace(0.0,1.0,101):
          for q in linspace(0.0,1.0,101):
            p=round(p,4)
            q=round(q,4)
            score = value(f,h,k,p,q)
            if score * 1.01 > bestScore:
              yield ( f, p, q, h, k, eInf(f,h), 1/signal(f, p, q, h, k), valueIFPQ(2,f,p,q), valueIFPQ(10000,f,p,q) )

def printOptimalPQ():
  print("Optimal choices for P and Q for varrious values:")
  for f, p, q, h, k, e, detThres, val2, val10000 in getOptimalPQ():
    print( 'h={}, k={:3}, f={:4}, p={:4}, q={:4},  epislon={:5}, signal={:5}'.format(h,k,f,p,q,e,detThres) )

print
print("Showing a plot shoing various points in the space. (Not nessicarly optimal ones)")
makePlot(getData)
print
printOptimalPQ()
print
makePlot(getOptimalPQ)