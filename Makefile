ROBOT_ENV=ROBOT_JAVA_ARGS=-Xmx120G
ROBOT=$(ROBOT_ENV) robot
RG_ENV=JAVA_OPTS=-Xmx120G
RG=$(RG_ENV) relation-graph

SCATLAS_KEEPRELATIONS = relations.txt

lung-ont.owl:
	echo 'Pulling Lung ontology to take its terms'
	wget -O $@ https://raw.githubusercontent.com/hubmapconsortium/ccf-validation-tools/master/owl/ccf_Lung_classes.owl

lung-seed.txt: lung-ont.owl
	$(ROBOT) query --input $< --query seed_class.sparql $@.tmp.txt
	cat $@.tmp.txt $(SCATLAS_KEEPRELATIONS) | sed '/term/d' >$@ && rm $@.tmp.txt

lung-annotations.owl: lung-ont.owl lung-seed.txt
	$(ROBOT) filter --input lung-ont.owl --term-file lung-seed.txt --select "self annotations" --output $@

uberon-base.owl:
	wget -O $@ http://purl.obolibrary.org/obo/uberon/uberon-base.owl

cl-base.owl:
	wget -O $@ http://purl.obolibrary.org/obo/cl/cl-base.owl

merged_imports.owl: uberon-base.owl cl-base.owl
	$(ROBOT) merge -i uberon-base.owl -i cl-base.owl -o $@

materialize-direct.nt: merged_imports.owl
	$(RG) --ontology-file $< --property 'http://purl.obolibrary.org/obo/BFO_0000050' --output-file $@

.PHONY: materialize-direct.nt

term.facts: lung-seed.txt
	cp $< $@.tmp.facts
	sed -e 's/^/</' -e 's/\r/>/' <$@.tmp.facts >$@ && rm $@.tmp.facts

rdf.facts: materialize-direct.nt
	sed 's/ /\t/' <$< | sed 's/ /\t/' | sed 's/ \.$$//' >$@

.PHONY: rdf.facts

ontrdf.facts: merged_imports.owl
	riot --output=ntriples $< | sed 's/ /\t/' | sed 's/ /\t/' | sed 's/ \.$$//' >$@

.PHONY: ontrdf.facts

complete-transitive.ofn: term.facts rdf.facts ontrdf.facts convert.dl
	souffle -c convert.dl
	sed -e '1s/^/Ontology(<http:\/\/purl.obolibrary.org\/obo\/lung-extended.owl>\n/' -e '$$s/$$/)/' <ofn.csv >$@ && rm ofn.csv

.PHONY: complete-transitive.ofn

extended.owl: complete-transitive.ofn lung-annotations.owl
	$(ROBOT) merge --input lung-annotations.owl --input complete-transitive.ofn \
					 remove --term $(SCATLAS_KEEPRELATIONS) --select complement --select object-properties --trim true -o $@

.PHONY: extended.owl

lung-extended.png: extended.owl ubergraph-style.json
	$(ROBOT) convert --input $< --output $<.json
	og2dot.js -s ubergraph-style.json $<.json > $<.dot 
	dot $<.dot -Tpng -Grankdir=LR > $@
	dot $<.dot -Tpdf -Grankdir=LR > $@.pdf

.PHONY: lung-extended.png
