"""
    get_pedigree(pedfile::AbstractString;header=false,separator=' ')
* Get pedigree informtion from a pedigree file.
* File format:

```
a 0 0
b 0 0
c a b
d a c
```
"""
function get_pedigree(pedfile::AbstractString;header=false,separator=' ')
  PedModule.mkPed(pedfile,header=header,separator=separator)
end

################################################################################
#set specific ModelTerm to random
#e.g. Animal, Animal*Age, Maternal
################################################################################
"""
    set_random(mme::MME,randomStr::AbstractString,ped::Pedigree, G;df=4)

* set variables as random polygenic effects with pedigree information **ped**, variances **G** whose degree of freedom **df** defaults to 4.0.

```julia
#single-trait (example 1)
model_equation  = "y = intercept + Age + Animal"
model           = build_model(model_equation,R)
ped             = get_pedigree(pedfile)
G               = 1.6
set_random(model,"Animal Animal*Age", ped,G)

#single-trait (example 2)
model_equation  = "y = intercept + Age + Animal + Animal*Age"
model           = build_model(model_equation,R)
ped             = get_pedigree(pedfile)
G               = [1.6   0.2
                   0.2  1.0]
set_random(model,"Animal Animal*Age", ped,G)

#multi-trait
model_equations = "BW = intercept + age + sex + Animal
                   CW = intercept + age + sex + Animal"
model           = build_model(model_equations,R);
ped             = get_pedigree(pedfile);
G               = [6.72   2.84
                   2.84  8.41]
set_random(model,"Animal", ped,G)
```
"""
function set_random(mme::MME,randomStr::AbstractString,ped::PedModule.Pedigree, G;df=4)
    pedTrmVec = split(randomStr," ",keep=false)  # "animal animal*age"

    #add model equation number; "animal" => "1:animal"
    res = []
    for trm in pedTrmVec
      for (m,model) = enumerate(mme.modelVec)
        strVec  = split(model,['=','+'])
        strpVec = [strip(i) for i in strVec]
        if trm in strpVec
          res = [res;string(m)*":"*trm]
        else
          info(trm," is not found in model equation ",string(m),".")
        end
      end
    end #"1:animal","1:animal*age"
    if length(res) != size(G,1)
      error("Dimensions must match. The covariance matrix (G) should be a ",length(res)," x ",length(res)," matrix.\n")
    end
    mme.pedTrmVec = res
    mme.ped = ped

    if mme.nModels!=1 #multi-trait
      mme.Gi = inv(G)
    else              #single-trait
      if issubtype(typeof(G),Number)==true #convert scalar G to 1x1 matrix
        G=reshape([G],1,1)
      end
      mme.GiOld = zeros(G)
      mme.GiNew = inv(G)
    end
    mme.df.polygenic=Float64(df)
    nothing
end

"""
    set_random(mme::MME,randomStr::AbstractString,G;df=4)

* set variables as i.i.d random effects with variances **G** whose degree of freedom **df** defaults to 4.0.

```julia
#single-trait (example 1)
model_equation  = "y = intercept + litter + sex"
model           = build_model(model_equation,R)
G               = 0.6
set_random(model,"litter",G)

#multi-trait
model_equations = "BW = intercept + litter + sex
                   CW = intercept + litter + sex"
model           = build_model(model_equations,R);
G               = [3.72  1.84
                   1.84  3.41]
set_random(model,"litter",G)
```
"""
function set_random(mme::MME,randomStr::AbstractString, G; df=4)
    G = map(Float64,G)
    df= Float64(df)
    randTrmVec = split(randomStr," ",keep=false)  # "herd"
    for trm in randTrmVec
      res = []
      for (m,model) = enumerate(mme.modelVec)
        strVec  = split(model,['=','+'])
        strpVec = [strip(i) for i in strVec]
        if trm in strpVec
          res = [res;string(m)*":"*trm] #add model number => "1:herd"
        else
          info(trm," is not found in model equation ",string(m),".")
        end
      end
      if length(res) != size(G,1)
        error("Dimensions must match. The covariance matrix (G) should be a ",length(res)," x ",length(res)," matrix.\n")
      end
      if issubtype(typeof(G),Number)==true #convert scalar G to 1x1 matrix
        G=reshape([G],1,1)
      end
      Gi = inv(G)

      term_string1 = res[1]
      term_array    = [mme.modelTermDict[term_string1]]
      for term_string in res[2:end]
        term_array  = [term_array;mme.modelTermDict[term_string]]
      end
      df           = df+length(term_array)
      scale        = G*(df-length(term_array)-1)  #G*(df-2)/df #from inv χ to inv-wishat
      randomEffect = RandomEffect(term_array,G,zeros(Gi),Gi,df,scale,zeros(1,1))
      push!(mme.rndTrmVec,randomEffect)
    end
    nothing
end
################################################################################
#*******************************************************************************
#following facts that scalar Inverse-Wishart(ν,S) = Inverse-Gamma(ν/2,S/2)=    *
#scale-inv-chi2(ν,S/ν), variances for random effects(non-marker) will be be    *
#sampled from Inverse-Wishart for coding simplicity thus prior for scalar      *
#variance is treated as a 1x1 matrix.                                          *
#*******************************************************************************
################################################################################

################################################################################
#duplicated code in addA and sample_variance_pedigree
#Need to be merged #MAY NOT
################################################################################
#The 1st time setting up MME,
#mme.GiOld = zeros(G),mme.GiNew = inv(G),mme.Rnew = mme.Rold= R
################################################################################
#construct MME for pedigree-based random effects part
function addA(mme::MME) #two terms,e.g.,"animal" and "maternal" may not near in MME
    pedTrmVec = mme.pedTrmVec
    for (i,trmi) = enumerate(pedTrmVec)
        pedTrmi  = mme.modelTermDict[trmi]
        startPosi  = pedTrmi.startPos
        endPosi    = startPosi + pedTrmi.nLevels - 1
        for (j,trmj) in enumerate(pedTrmVec)
            pedTrmj  = mme.modelTermDict[trmj]
            startPosj= pedTrmj.startPos
            endPosj  = startPosj + pedTrmj.nLevels - 1
            #lamda version (single trait) or not (multi-trait)
            myaddA   = (mme.nModels!=1)?(mme.Ai*mme.Gi[i,j]):(mme.Ai*(mme.GiNew[i,j]*mme.RNew - mme.GiOld[i,j]*mme.ROld))
            mme.mmeLhs[startPosi:endPosi,startPosj:endPosj] =
            mme.mmeLhs[startPosi:endPosi,startPosj:endPosj] + myaddA
        end
    end
end

################################################################################
#construct MME for iid random effects part
#single-trait: lamda version, assume effects are independent, e.g., litter and groups
#multi-trait: same effects in 2 traits are NOT correlated,e.g., 1:litter, 2:litter
################################################################################
function addLambdas(mme::MME)
    for random_term in mme.rndTrmVec
      term_array = random_term.term_array
      for (i,termi) = enumerate(term_array)
          startPosi  = termi.startPos
          endPosi    = startPosi + termi.nLevels - 1
          for (j,termi) in enumerate(term_array)
            startPosj   = termi.startPos
            endPosj     = startPosj + termi.nLevels - 1
            myeye       = speye(termi.nLevels)
            myaddLambda = (mme.nModels!=1)?(myeye*random_term.GiNew[i,j]):(myeye*(random_term.GiNew[i,j]*mme.RNew - random_term.GiOld[i,j]*mme.ROld))
            mme.mmeLhs[startPosi:endPosi,startPosj:endPosj] =
            mme.mmeLhs[startPosi:endPosi,startPosj:endPosj] + myaddLambda
          end
      end
    end
end
