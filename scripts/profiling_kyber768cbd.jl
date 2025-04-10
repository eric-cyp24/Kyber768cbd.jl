using Dates: Time, Second
using Kyber768cbd: loaddata, Kyber768_profiling
import TemplateAttack


### Parameters ##########
include("Parameters.jl")
TracesDIR = normpath( joinpath(@__DIR__, "../data/Traces/") )
skipexist = false
###

Dir        = DirHPFOs
Targetlist = [:DK2] #deviceslist
POIe_left, POIe_right  = 40, 80
nicv_th  , buf_nicv_th = 0.001, 0.004
IVs        = [:Buf, :XY, :X] #[:Buf, :XY, :X, :Y, :S]
IVs        = [:X] #[:Buf, :XY, :X, :Y, :S]
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
        Traces = loaddata( joinpath(INDIR, "traces_lanczos2_25_proc.h5") )
        Buf    = :Buf in IVs ? loaddata( joinpath(INDIR, "Buf_proc.h5") ) : nothing
        X      = :X   in IVs ? loaddata( joinpath(INDIR,   "X_proc.h5") ) : nothing
        Y      = :Y   in IVs ? loaddata( joinpath(INDIR,   "Y_proc.h5") ) : nothing
        S      = :S   in IVs ? loaddata( joinpath(INDIR,   "S_proc.h5") ) : nothing
        XY     = :XY  in IVs ? loaddata( joinpath(INDIR,  "XY_proc.h5") ) : nothing

        # profiling
        println("*** Device: $dev *************************")
        secs = @elapsed Kyber768_profiling(INDIR, OUTDIR, Traces; X, Y, S, Buf, XY,
                                           POIe_left, POIe_right, nicv_th, buf_nicv_th, skipexist)
        ts = Time(0) + Second(floor(secs))
        println("time: $ts -> profiling $TgtDir")
        println("**********************************************************")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    mkpath(TMPDIR)
    global TMPFILE, io = mktemp(TMPDIR); close(io)
    TemplateAttack.TMPFILE = TMPFILE
    println("TMPFILE: ",TMPFILE)
    main()
    isempty(readdir(TMPDIR)) && rm(TMPDIR)
end
