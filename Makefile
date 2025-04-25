# GNU Make

.DELETE_ON_ERROR:

# rasterizing PDF figures (e.g. for README.md)
DPI=250
GS_OPTIONS=-dSAFER -dNOPAUSE -q -dBATCH -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dAlignToPixels=0 -r$(DPI) -sDEVICE=png16m
%.png: %.pdf
	gs $(GS_OPTIONS) -sOutputFile=$@ $<

results/%.pdf: scripts/%.tex
	pdflatex -halt-on-error -output-directory results $<
	while grep 'Rerun to get ' results/$*.log ; do pdflatex -output-directory results $< ; done

THREADOPT=-t4
#DATA_DIR=data

# this profiling aand attack run requires about 25 GB file space (not counting JULIA_DEPOT_PATH)
option_1: instantiate
	julia --project scripts/downloaddata.jl
	julia --project scripts/profiling_kyber768cbd.jl
	julia --project $THREADOPT scripts/attack_kyber768cbd_Buf_singletrace.jl
	julia --project $THREADOPT scripts/attack_kyber768cbd_Buf_singletrace.jl --targetOP Encaps
	$(MAKE) results/SuccessRateTables.png
	$(MAKE) results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png

# more thrifty download and deletion order, requires only about 12 GB file space
option_2: instantiate
	julia --project scripts/downloaddata.jl --profiling
	julia --project scripts/profiling_kyber768cbd.jl
	julia --project scripts/deletedata.jl --profiling
	julia --project scripts/downloaddata.jl --attack
	julia --project $THREADOPT scripts/attack_kyber768cbd_Buf_singletrace.jl
	julia --project $THREADOPT scripts/attack_kyber768cbd_Buf_singletrace.jl --targetOP Encaps
	julia --project scripts/deletedata.jl --attack
	$(MAKE) results/SuccessRateTables.png
	$(MAKE) results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png

# install and precompile all Julia dependencies of this project
instantiate:
	julia --project -e 'import Pkg; Pkg.instantiate()'

# rules for building the tables and figures

results/KeyGen_Multi-Board_Single-Trace_Attack_Success_Rate.tex results/Encaps_Multi-Board_Single-Trace_Attack_Success_Rate.tex: scripts/h5result2latextable_multiboardsingletrace.jl
	julia --project scripts/h5result2latextable_multiboardsingletrace.jl

results/SuccessRateTables.pdf: results/KeyGen_Multi-Board_Single-Trace_Attack_Success_Rate.tex \
	                       results/Encaps_Multi-Board_Single-Trace_Attack_Success_Rate.tex

results/EMAdjustmentFigures.pdf: results/traces_and_XY_templates.png results/traces_and_XY_templates_EMadj.png \
	                         results/traces_and_X_templates.png  results/traces_and_X_templates_EMadj.png

results/traces_and_XY_templates.png results/traces_and_XY_templates_EMadj.png: scripts/figure_emadj_templates.jl
	julia --project $< --variable XY --output $@

results/traces_and_X_templates.png results/traces_and_X_templates_EMadj.png: scripts/figure_emadj_templates.jl
	julia --project $< --variable X --output $@

results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png: results/EMAdjustmentFigures.pdf
	gs $(GS_OPTIONS) -r500 -sOutputFile=results/EMAdjustmentFigures%d.png $<

tests:
	julia --project -e 'import Pkg; Pkg.test(["EMAlgorithm", "LeakageAssessment", "TemplateAttack"])'

Kyber768cbd.zip:
	git clone --recursive https://github.com/eric-cyp24/Kyber768cbd.jl Kyber768cbd
	cd Kyber768cbd && git submodule update
	rm -rf Kyber768cbd/.git* Kyber768cbd/packages/*/.git*
	zip -r $@ Kyber768cbd

install_figures: results/SuccessRateTables.png results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png
	cp $+ scripts/

clean:
	rm -rf data/ results/
