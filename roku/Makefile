# Roku channel build + sideload.
#
#   make package                       -> build/ReolinkWall.zip
#   make install ROKU_HOST=1.2.3.4 ROKU_PASS=devpw
#   make delete  ROKU_HOST=1.2.3.4 ROKU_PASS=devpw
#
# Enable Developer Mode on the Roku first:
#   Home x3, Up x2, Right, Left, Right, Left, Right -> set a password, note the IP.

APP      := ReolinkWall
BUILD    := build
ZIP      := $(BUILD)/$(APP).zip
BACKEND  ?= http://reolinkstreamer.lan:8088
ROKU_USER?= rokudev

SRC := manifest source components images

.PHONY: package install delete clean

package: clean
	@mkdir -p $(BUILD)/stage
	@cp -R $(SRC) $(BUILD)/stage/
	@# bake the backend URL into config.brs
	@sed -i '' 's#@@BACKEND_URL@@#$(BACKEND)#g' $(BUILD)/stage/components/config.brs 2>/dev/null \
	  || sed -i 's#@@BACKEND_URL@@#$(BACKEND)#g' $(BUILD)/stage/components/config.brs
	@cd $(BUILD)/stage && zip -q -r ../$(APP).zip . -x '.*'
	@echo "built $(ZIP)  (backend = $(BACKEND))"

install: package
	@test -n "$(ROKU_HOST)" || { echo "set ROKU_HOST=<roku-ip>"; exit 1; }
	@test -n "$(ROKU_PASS)" || { echo "set ROKU_PASS=<dev-password>"; exit 1; }
	curl -s --anyauth -u "$(ROKU_USER):$(ROKU_PASS)" \
	  -F "mysubmit=Install" -F "archive=@$(ZIP)" -F "passwd=" \
	  "http://$(ROKU_HOST)/plugin_install" | grep -o 'Identical\|Install Success\|Application Received\|Error[^<]*' || true
	@echo "-> check the TV"

delete:
	curl -s --anyauth -u "$(ROKU_USER):$(ROKU_PASS)" \
	  -F "mysubmit=Delete" -F "archive=" \
	  "http://$(ROKU_HOST)/plugin_install" >/dev/null && echo "deleted"

clean:
	@rm -rf $(BUILD)
