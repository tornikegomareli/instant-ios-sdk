if which swiftformat >/dev/null; then
	swiftformat . --swiftversion 5
else
	${SRCROOT}/Tools/swiftformat . --swiftversion 5
fi
