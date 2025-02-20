using StatsBase:sample

# Profiling for Kyber768 with targeted intermediate variables: Buf, XY(β), X, Y, S
function Kyber768_profiling(INDIR, OUTDIR, Traces; X=nothing, Y=nothing, S=nothing, Buf=nothing, XY=nothing,
                            POIe_left=0, POIe_right=0, nicv_th=0.001, buf_nicv_th=0.004, nvalid=nothing)
    if !isnothing(X)
        numofcomponents, priors = 3, :uniform
        fn = "Templates_X_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for X: $outfile")
        if !isfile(outfile)
            Templates_X = runprofiling( X, Traces; nicv_th, POIe_left, POIe_right,
                                                   priors, numofcomponents, outfile, nvalid);
        end
    end

    if !isnothing(Y)
        numofcomponents, priors = 3, :uniform
        fn = "Templates_Y_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for Y: $outfile")
        if !isfile(outfile)
            Templates_Y = runprofiling( Y, Traces; nicv_th, POIe_left, POIe_right,
                                                   priors, numofcomponents, outfile, nvalid);
        end
    end

    if !isnothing(S)
        numofcomponents, priors = 4, :binomial
        fn = "Templates_S_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for S: $outfile")
        if !isfile(outfile)
            Templates_S = runprofiling( S, Traces; nicv_th, POIe_left, POIe_right,
                                                   priors, numofcomponents, outfile, nvalid);
        end
    end

    if !isnothing(Buf)
        numofcomponents, priors = 16, :uniform
        fn = "Templates_Buf_proc_nicv$(string(buf_nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for Buf: $outfile")
        if !isfile(outfile)
            Templates_Buf = runprofiling( Buf, Traces; nicv_th=buf_nicv_th, POIe_left, POIe_right,
                                                       priors, numofcomponents, outfile, nvalid);
        end
    end

    if !isnothing(XY)
        numofcomponents, priors = 15, :uniform
        fn = "Templates_XY_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for XY: $outfile")
        if !isfile(outfile)
            Templates_XY = runprofiling( XY, Traces; nicv_th, POIe_left, POIe_right,
                                                     priors, numofcomponents, outfile, nvalid);
        end
    end
end

# Multi-device training
function pooledTraces(MixDIR, devices, trlen, ntraces, ntest=500)
    isdir(MixDIR) || mkpath(joinpath(MixDIR,"Templates/")) # create Dir if not exist
    nprofile = Int((ntraces/length(devices))÷1000)*1000-ntest
    numtr    = length(devices)*(ntest+nprofile)
    TrFILE   = h5open(joinpath(MixDIR,"traces_lanczos2_25_proc.h5"),"w")
    BufFILE  = h5open(joinpath(MixDIR,"Buf_proc.h5"),"w")
    XFILE    = h5open(joinpath(MixDIR,"X_proc.h5"),"w")
    YFILE    = h5open(joinpath(MixDIR,"Y_proc.h5"),"w")
    SFILE    = h5open(joinpath(MixDIR,"S_proc.h5"),"w")
    XYFILE   = h5open(joinpath(MixDIR,"XY_proc.h5"),"w")
    Traces   = create_dataset( TrFILE, "data", datatype(Float32), dataspace(trlen,numtr))
    Buf      = create_dataset(BufFILE, "data", datatype(  UInt8), dataspace(    8,numtr))
    X        = create_dataset(  XFILE, "data", datatype(  Int16), dataspace(   16,numtr))
    Y        = create_dataset(  YFILE, "data", datatype(  Int16), dataspace(   16,numtr))
    S        = create_dataset(  SFILE, "data", datatype(  Int16), dataspace(   16,numtr))
    XY       = create_dataset( XYFILE, "data", datatype(  Int16), dataspace(   16,numtr))
    for (n,dev) in enumerate(devices)
        print("$n/$(length(devices)) sampling from $dev: \r")
        selected  = sample(1:ntraces, nprofile+ntest; replace=false)
        sort!(view(selected,1:nprofile));sort!(view(selected,nprofile+1:nprofile+ntest))
        print("$n/$(length(devices)) sampling from $dev: loading Traces...   \r")
        devTraces = loaddata(joinpath(srcDir(dev), "traces_lanczos2_25_proc.h5"))
        Trtmp = devTraces[:,selected]
        print("$n/$(length(devices)) sampling from $dev: writing Traces...   \r")
        Traces[:,(n-1)*nprofile+1 :      n*nprofile] = Trtmp[:,1:nprofile]
        Traces[:,   end-n*ntest+1 : end-(n-1)*ntest] = Trtmp[:,nprofile+1:end]
        print("$n/$(length(devices)) sampling from $dev: ")
        print("Buf  ")
        devBuf    = loaddata(joinpath(srcDir(dev), "Buf_proc.h5"))
        Buf[:,(n-1)*nprofile+1 :      n*nprofile] = view(devBuf,:,selected[1:nprofile])
        Buf[:,   end-n*ntest+1 : end-(n-1)*ntest] = view(devBuf,:,selected[nprofile+1:end])
        print("X  ")
        devX      = loaddata(joinpath(srcDir(dev), "X_proc.h5"))
        X[:,(n-1)*nprofile+1 :      n*nprofile] = view(devX,:,selected[1:nprofile])
        X[:,   end-n*ntest+1 : end-(n-1)*ntest] = view(devX,:,selected[nprofile+1:end])
        print("Y  ")
        devY      = loaddata(joinpath(srcDir(dev), "Y_proc.h5"))
        Y[:,(n-1)*nprofile+1 :      n*nprofile] = view(devY,:,selected[1:nprofile])
        Y[:,   end-n*ntest+1 : end-(n-1)*ntest] = view(devY,:,selected[nprofile+1:end])
        print("S  ")
        devS      = loaddata(joinpath(srcDir(dev), "S_proc.h5"))
        S[:,(n-1)*nprofile+1 :      n*nprofile] = view(devS,:,selected[1:nprofile])
        S[:,   end-n*ntest+1 : end-(n-1)*ntest] = view(devS,:,selected[nprofile+1:end])
        print("XY  ")
        devXY     = loaddata(joinpath(srcDir(dev), "XY_proc.h5"))
        XY[:,(n-1)*nprofile+1 :      n*nprofile] = view(devXY,:,selected[1:nprofile])
        XY[:,   end-n*ntest+1 : end-(n-1)*ntest] = view(devXY,:,selected[nprofile+1:end])
        print("\r                                            \r")
    end
    close(TrFILE)
    close(BufFILE)
    close(XFILE)
    close(YFILE)
    close(SFILE)
    close(XYFILE)
end

