using Dates:Time,Second
using Kyber768cbd:loaddata, Kyber768_profiling, pooledTraces

### Parameters ########
include("Parameters.jl")
ntraces   = 192000
trlen     = 10440
ntest     = 500
###

Dir = DirHPFOs
POIe_left, POIe_right = 40, 80
nicv_th, buf_nicv_th  = 0.001, 0.004
#######################


function main()
    # profiling for mixed traces
    for idx in devpoolsidx
        # setting filepaths, creating pooled training traces
        devices = devicespools[idx]
        MixDIR  = joinpath(TracesDIR, pooledDir(devices), "lanczos2_25/")
        nvalid  = length(devices)*ntest
        pooledTraces(MixDIR, devices, ntest)
        OUTDIR  = joinpath(MixDIR, "Templates_POIe$(POIe_left)-$(POIe_right)/")
        isdir(OUTDIR) || mkpath(OUTDIR)

        # loading data
        Traces = loaddata( joinpath(MixDIR, "traces_lanczos2_25_proc.h5"); datapath="data")
        Buf    = loaddata( joinpath(MixDIR, "Buf_proc.h5"); datapath="data")
        X      = loaddata( joinpath(MixDIR,   "X_proc.h5"); datapath="data")
        Y      = loaddata( joinpath(MixDIR,   "Y_proc.h5"); datapath="data")
        S      = loaddata( joinpath(MixDIR,   "S_proc.h5"); datapath="data")
        XY     = loaddata( joinpath(MixDIR,  "XY_proc.h5"); datapath="data")

        # profiling on pooled traces
        println("*** Device: $idx *************************")
        secs = @elapsed Kyber768_profiling(MixDIR, OUTDIR, Traces; Buf, X, Y, S, XY, nvalid,
                                           POIe_left, POIe_right, nicv_th, buf_nicv_th)
        ts = Time(0) + Second(floor(secs))
        println("time: $ts -> profiling $devices")
        println("**********************************************************")

        # remove files
        rm(joinpath(MixDIR, "traces_lanczos2_25_proc.h5"))
        rm(joinpath(MixDIR, "Buf_proc.h5"))
        rm(joinpath(MixDIR,   "X_proc.h5"))
        rm(joinpath(MixDIR,   "Y_proc.h5"))
        rm(joinpath(MixDIR,   "S_proc.h5"))
        rm(joinpath(MixDIR,  "XY_proc.h5"))
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
