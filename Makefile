# GNU Make

# rasterizing PDF figures (e.g. for README.md)
DPI=250
GS_OPTIONS=-dSAFER -dNOPAUSE -q -dBATCH -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dAlignToPixels=0 -r$(DPI) -sDEVICE=png16m
%.png: %.pdf
	gs $(GS_OPTIONS) -sOutputFile=$@ $<

THREADOPT=-t4
#DATA_DIR=data

# this run requires about 25 GB file space (not counting JULIA_DEPOT_PATH)
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

scripts/SuccessRateTables.tex: scripts/h5result2latextable_multiboardsingletrace.jl
	julia --project scripts/h5result2latextable_multiboardsingletrace.jl

results/SuccessRateTables.pdf: scripts/SuccessRateTables.tex
	pdflatex -output-directory results scripts/SuccessRateTables.tex

results/EMAdjustmentFigures.pdf:
	julia --project scripts/figure_emadj_templates.jl --variable XY --output results/traces_and_XY_templates.png
	julia --project scripts/figure_emadj_templates.jl --variable X --output results/traces_and_X_templates.png
	pdflatex -output-directory results scripts/EMAdjustmentFigures.tex

results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png: results/EMAdjustmentFigures.pdf
	gs $(GS_OPTIONS) -r500 -sOutputFile=results/EMAdjustmentFigures%d.png $<

tests:
	julia --project -e 'import Pkg; Pkg.test(["EMAlgorithm", "LeakageAssessment", "TemplateAttack"])'

Kyber768cbd.zip:
	git clone --recursive https://github.com/eric-cyp24/Kyber768cbd.jl Kyber768cbd
	cd Kyber768cbd && git submodule update
	rm -rf Kyber768cbd/.git* Kyber768cbd/packages/*/.git*
	zip -r $@ Kyber768cbd

install_figures:
	cp results/SuccessRateTables.png scripts/LaTeX_tables.png
	cp results/EMAdjustmentFigures[12].png scripts/

clean:
	rm -rf data
	rm -rf results
	rm -f scripts/SuccessRateTables.*
	rm -f results/EMAdjustmentFigures*
