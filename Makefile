GEN_FILES=$(shell cat instructions_to_generate.txt | sed 's/$$/.gen.odin/g')
./aarch64asm: main.odin $(GEN_FILES)
	odin build .
./armspec.tar.gz: 
	wget 'https://developer.arm.com/-/media/developer/products/architecture/armv8-a-architecture/A64_v82A_ISA_xml_00bet3.1.tar.gz' -O $@
	mkdir -p armspec
	cd armspec; tar -xf ../armspec.tar.gz
./instructions.json: ./instructions_to_generate.txt armspec.tar.gz
	rm -rf ./instructions/*
	for i in $$(cat ./instructions_to_generate.txt); do \
		./parse_armspec.py ./armspec/ISA_v82A_A64_xml_00bet3.1/$$i.xml > instructions/$$i.json ; \
	done
	jq -s '.' ./instructions/*.json > ./instructions.json
$(GEN_FILES): ./gen.bin ./instructions.json
	./gen.bin ./instructions.json ./
	@touch $(GEN_FILES)
./gen.bin: ./gen/generate.odin
	odin build gen

clean:
	rm -rf *.gen.odin ./gen.bin ./instructions.json ./armspec.tar.gz ./armspec
