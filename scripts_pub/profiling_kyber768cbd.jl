using Dates: Time, Second
using Kyber768cbd: loaddata, Kyber768_profiling
import TemplateAttack


### Parameters ##########
include("Parameters.jl")
TracesDIR = joinpath(@__DIR__, "../data/Traces-pub/")
###

Dir        = DirHPFOs
Targetlist = [:DK2] #deviceslist
POIe_left, POIe_right  = 40, 80
nicv_th  , buf_nicv_th = 0.001, 0.004
IVs        = [:Buf] #[:Buf, :XY, :X, :Y, :S]
#########################


function main()
    # profiling for different devices
    for dev in Targetlist
        # setting filepaths
        TgtDir = Dir[dev]
        INDIR  = joinpath(TracesDIR, TgtDir,"lanczos2_25/")
        OUTDIR = joinpath(INDIR,"Templates_POIe$(POIe_left)-$(POIe_right)/")
        isdir(OUTDIR) || mkpath(OUTDIR)

        # loading data
        Traces = loaddata( joinpath(INDIR, "traces_lanczos2_25_proc.npy") )
        Buf    = :Buf in IVs ? loaddata( joinpath(INDIR, "Buf_proc.npy") ) : nothing
        X      = :X   in IVs ? loaddata( joinpath(INDIR,   "X_proc.npy") ) : nothing
        Y      = :Y   in IVs ? loaddata( joinpath(INDIR,   "Y_proc.npy") ) : nothing
        S      = :S   in IVs ? loaddata( joinpath(INDIR,   "S_proc.npy") ) : nothing
        XY     = :XY  in IVs ? loaddata( joinpath(INDIR,  "XY_proc.npy") ) : nothing

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
