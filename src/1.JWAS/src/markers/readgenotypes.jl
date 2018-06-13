function readgenotypes(file::AbstractString;separator=',',header=false,center=true) 
    #separator is ',' based on the default file format in JWAS_public_addgenotypes
    #println("The delimiters in file $file is ",separator,"  .")

    myfile = open(file)
    #get number of columns
    row1   = split(readline(myfile),[separator,','],keep=false) #separator is ","

    if header==true
      markerID=row1[2:end]  #skip header
    else
      markerID= row1[:]
      #assume header indicates the first column of row1
    end
    
    #set types for each column and get number of markers
    ncol= length(row1)
    etv = Array{DataType}(ncol)
    fill!(etv,Float64) 
    etv[1]=String
    close(myfile)

    #read genotypes
    df = CSV.read(file, types=etv, delim = separator, header=header)


    obsID=convert(Array,df[2:end,1])
    genotypes = map(Float64,convert(Array,df[2:end,2:end])) 
    nObs,nMarkers = size(genotypes)

    if center==true
        markerMeans = center!(genotypes) #centering
    else
        markerMeans = center!(copy(genotypes))  #get marker means
    end
    p             = markerMeans/2.0
    sum2pq        = (2*p*(1-p)')[1,1]

    return Genotypes(obsID,markerID,nObs,nMarkers,p,sum2pq,center,genotypes)
end

#M is of type: Array{Float64,2} or DataFrames
function readgenotypes(M::DataFrames.DataFrame;header=false,separator=' ',center=true)#improve later
    genotypes  = map(Float64,convert(Array,M[:,2:end]))
    markerID = ["NA"] #cannot find a method for extracting columns names in dataframes
    obsID = convert(Array,M[:,1]) 
    nObs,nMarkers = size(genotypes)

    if center==true
        markerMeans = center!(genotypes) #centering
    else
        markerMeans = center!(copy(genotypes))  #get marker means
    end
    p             = markerMeans/2.0
    sum2pq       = (2*p*(1-p)')[1,1]

    return Genotypes(obsID,markerID,nObs,nMarkers,p,sum2pq,center,genotypes)
end

function readgenotypes(M::Array{Float64,2};header=false,separator=' ',center=true)
    genotypes = map(Float64,M)
    obsID     = ["NA"]
    markerID  = ["NA"]
    nObs,nMarkers = size(genotypes)

    if center==true
        markerMeans = center!(genotypes) #centering
    else
        markerMeans = center!(copy(genotypes))  #get marker means
    end
    p             = markerMeans/2.0
    sum2pq       = (2*p*(1-p)')[1,1]

    return Genotypes(obsID,markerID,nObs,nMarkers,p,sum2pq,center,genotypes)
end
