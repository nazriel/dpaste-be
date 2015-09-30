module app;

shared static this()
{
	import vibe.core.args: readOption, readRequiredOption;
	import vibe.http.router: URLRouter;
	import vibe.core.core: runTask, Task, exitEventLoop;
	import vibe.http.server;
	import vibe.core.log;
	
	import std.functional: toDelegate;
	import std.file: exists, readLink;
	import std.path: dirName;
	import std.stdio: stdout;

	import dpaste.backend.common;
	import dpaste.backend.daemon;
	import dpaste.backend.worker: spawnWorker;

	string appDir = readLink("/proc/self/exe").dirName();

	setLogLevel(LogLevel.debug_);
	auto logger = cast(shared) new FileLogger(stdout, stdout);
	registerLogger(logger);
	logInfo("appDir %s", appDir);

	ushort listenPort;
	string listenIpAddress = "0.0.0.0";
	string configFilePath = appDir ~ "/config.json";

	readOption("c|config", &configFilePath, "Full path to the configuration file (.json)");
	readOption("l|address", &listenIpAddress, "IP address on which service should listen - 0.0.0.0 for all interfaces");
	listenPort = readRequiredOption!ushort("p|port", "Port on which service should listen");

	URLRouter router = new URLRouter;
	router.post("/", &spawnWorker);

	auto settings = new HTTPServerSettings;
	settings.bindAddresses = [listenIpAddress];
	settings.port = listenPort;
	settings.options = HTTPServerOption.defaults | HTTPServerOption.parseJsonBody;
	//settings.sessionStore = new MemorySessionStore;

	if (!readConfigFile(configFilePath, gConfiguration))
	{
		logFatal("Couldn't start instance due to invalid configuration. Check log file for details");
		gIsRunning = false;
		exitEventLoop();
		return;
	}

	getAvailableUsers(gConfiguration, gAvailableUsers);

	gIsRunning = true;

	runTask(toDelegate(&monitorConfigChanges), configFilePath);

	listenHTTP(settings, router);
}
