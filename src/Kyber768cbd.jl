module Kyber768cbd

using TemplateAttack
using TemplateAttack:loaddata, trace_normalize, trace_normalize!, key_guessing
using EMAlgorithm:emalg_addprocs, rmprocs

include("Parameters.jl")

include("profiling.jl")
export loaddata, Kyber768_profiling, pooledTraces

include("attack_singletrace_Buf.jl")
export emalg_add_procs, rmprocs, singletraceattacks,
       loadTemplates, writeTemplates, writeTemplates_ldaspace,
       tracesnormalize, Templates_EMadj!,
       key_guessing, guessing_entropy, success_rate


end # module Kyber768cbd
