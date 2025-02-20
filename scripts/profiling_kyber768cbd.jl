using Dates:Time,Second
using TemplateAttack
using TemplateAttack:loaddata


### Parameters ##########
include("Parameters.jl")
TracesDIR = joinpath(@__DIR__, "../data/Traces-O3/")
###

Dir        = DirHPFO3
Targetlist = [:RS1, :RS2] #deviceslist
POIe_left, POIe_right  = 40, 80
nicv_th  , buf_nicv_th = 0.001, 0.004
IVs        = [:Buf, :XY, :X, :Y, :S] #[:Buf, :XY, :X, :Y, :S]
#########################


function Kyber768_profiling(INDIR, OUTDIR, Traces; X=nothing, Y=nothing, S=nothing, Buf=nothing, XY=nothing, 
                            POIe_left=0, POIe_right=0, nicv_th=0.001, buf_nicv_th=0.004)
    if !isnothing(X)
        numofcomponents, priors = 3, :uniform
        fn = "Templates_X_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for X: $outfile")
        if !isfile(outfile)
            Templates_X = runprofiling( X, Traces; nicv_th, POIe_left, POIe_right, 
                                                   priors, numofcomponents, outfile);
        end
    end

    if !isnothing(Y)
        numofcomponents, priors = 3, :uniform
        fn = "Templates_Y_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for Y: $outfile")
        if !isfile(outfile)
        Templates_Y = runprofiling( Y, Traces; nicv_th, POIe_left, POIe_right, 
                                               priors, numofcomponents, outfile);
        end
    end

    if !isnothing(S)
        numofcomponents, priors = 4, :binomial
        fn = "Templates_S_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for S: $outfile")
        if !isfile(outfile)
        Templates_S = runprofiling( S, Traces; nicv_th, POIe_left, POIe_right, 
                                               priors, numofcomponents, outfile);
        end
    end

    if !isnothing(Buf)
        numofcomponents, priors = 16, :uniform
        fn = "Templates_Buf_proc_nicv$(string(buf_nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for Buf: $outfile")
        if !isfile(outfile)
        Templates_Buf = runprofiling( Buf, Traces; nicv_th=buf_nicv_th, POIe_left, POIe_right, 
                                                   priors, numofcomponents, outfile);
        end
    end

    if !isnothing(XY)
        numofcomponents, priors = 15, :uniform
        fn = "Templates_XY_proc_nicv$(string(nicv_th)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
        outfile = joinpath(OUTDIR, fn)
        println("profiling for XY: $outfile")
        if !isfile(outfile)
        Templates_XY = runprofiling( XY, Traces; nicv_th, POIe_left, POIe_right, 
                                                   priors, numofcomponents, outfile);
        end
    end
end


function main()
    # profiling for different devices
    for dev in Targetlist
        # setting filepaths
        TgtDir = Dir[dev]
        INDIR  = joinpath(TracesDIR, TgtDir,"lanczos2_25/")
        OUTDIR = joinpath(INDIR,"Templates_POIe$(POIe_left)-$(POIe_right)/")
        isdir(OUTDIR) || mkpath(OUTDIR)

        # loading data
        Traces = loaddata( joinpath(INDIR, "traces_lanczos2_25_proc.h5") )
        Buf    = :Buf in IVs ? loaddata( joinpath(INDIR, "Buf_proc.h5") ) : nothing
        X      = :X   in IVs ? loaddata( joinpath(INDIR,   "X_proc.h5") ) : nothing
        Y      = :Y   in IVs ? loaddata( joinpath(INDIR,   "Y_proc.h5") ) : nothing
        S      = :S   in IVs ? loaddata( joinpath(INDIR,   "S_proc.h5") ) : nothing
        XY     = :XY  in IVs ? loaddata( joinpath(INDIR,  "XY_proc.h5") ) : nothing
        if XY != (X .+ (Y .<<2)) 
            println("something is swong with XY_proc.h5")
            XY = (X .+ (Y .<<2))
        end

        # profiling
        println("*** Device: $dev *************************")
        secs = @elapsed Kyber768_profiling(INDIR, OUTDIR, Traces; X, Y, S, Buf, XY,
                                           POIe_left, POIe_right, nicv_th, buf_nicv_th)
        ts = Time(0) + Second(floor(secs))
        println("time: $ts -> profiling $TgtDir")
        println("**********************************************************")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    for i in 0:20
        if !isfile(TMPFILE*".$i")
            global TMPFILE *= ".$i"
            TemplateAttack.TMPFILE = TMPFILE
            touch(TMPFILE)
            break
        end
    end
    println("TMPFILE: ",TMPFILE)
    main()
    rm(TMPFILE)
end
