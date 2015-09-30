module dpaste.backend.common;

import vibe.data.json;
import vibe.core.core;
import vibe.core.log;

import std.process: ProcessPipes;
import core.time: Duration;

protected
{
	bool gIsRunning;
	Json gConfiguration;
	User[uint] gActiveUsers;
	User[uint] gAvailableUsers;
}

public:

struct User
{
	enum Permissions : string
	{
		guest = "guest",
		registered = "registered",
		dlang = "dlang"
	}

	string homePath;
	string name;
	uint id;
	uint groupId;

	Permissions permission;
}

bool readConfigFile(string configFilePath, ref Json config)
{
	import std.file: exists;
	import vibe.core.file: openFile, FileMode, FileStream;
	import vibe.utils.string: stripUTF8Bom;
	import vibe.stream.operations: readAll;

	if (!configFilePath.exists())
	{
		logFatal(
			"Configuration file in given location: '%s' doesn't exist! "
			"Make sure you provide full path to the file", configFilePath
		);
	}

	FileStream f = openFile(configFilePath, FileMode.read);
	scope(exit) f.close();
	string configContent = stripUTF8Bom(cast(string) f.readAll());

	Json cfg;
	try 
	{
		logTrace("Configuration file raw content: %s", configContent);
		cfg = parseJsonString(configContent, configFilePath);
	} 
	catch (JSONException e)
	{
		logError("Couldn't parse '%s' configuration file: %s", configFilePath, e.msg);
		return false;
	}

	/*
	if ("users" !in cfg)
	{
		logError("'users' object containing system users used for compilation is missing");
		return false;
	}

	if ("compilers" !in cfg)
	{
		logError("'compilers' object containing available compilers is missing");
		return false;
	}
	*/

	config = cfg;

	return true;
}

auto processInputOutput(ProcessPipes process, string input, Duration timeout)
{
	import std.array: appender;
	import std.process: ProcessException, kill, tryWait;
	import std.typecons: Tuple;

	import core.sys.posix.signal: SIGKILL, SIGINT;
	import core.sys.posix.fcntl: fcntl, F_SETFL, O_NONBLOCK;
	import core.sys.posix.unistd;
	import core.time: seconds;

	alias Ret = Tuple!(int, "status", string, "stdout", string, "stderr");

	auto stdout = appender!(char[])();
	auto stderr = appender!(char[])();
	
	scope(exit)
	{
		import std.exception: collectException;

		logTrace("Terminating worker process (PID: %d)", process.pid.processID);
		collectException!ProcessException(process.pid.kill(SIGINT));
		vibe.core.core.sleep(1.seconds);

		// Shouldn't really happen... just in case
		if (!tryWait(process.pid).terminated)
		{
			process.pid.kill(SIGKILL);
		}
	}
	fcntl(process.stdout.fileno, F_SETFL, O_NONBLOCK);
	fcntl(process.stderr.fileno, F_SETFL, O_NONBLOCK);
	
	scope FileDescriptorEvent stdoutReadEvt = createFileDescriptorEvent(
		process.stdout.fileno, 
		FileDescriptorEvent.Trigger.read
	);

	scope FileDescriptorEvent stderrReadEvt = createFileDescriptorEvent(
		process.stderr.fileno, 
		FileDescriptorEvent.Trigger.read
	);
	
	process.stdin.writeln(input);
	process.stdin.flush();
	process.stdin.close();
	
	if (!stdoutReadEvt.wait(timeout, FileDescriptorEvent.Trigger.read))
	{
		logTrace("stdoutReadEvt.wait timed out");
	}

	if (!stderrReadEvt.wait(timeout, FileDescriptorEvent.Trigger.read))
	{
		logTrace("stderrReadEvt.wait timed out");
	}

	/* Get all stdout */
	char[1024] buf = void;
	ptrdiff_t len = 0;
	while ((len = read(process.stdout.fileno, &buf[0], buf.length)) == buf.length)
	{
		logTrace("Stdout ...");
		stdout.put(buf[]);
	}
	
	if (len > 0)
	{
		stdout.put(buf[0..len]);
	}

	/* Get all stderr */
	buf = buf.init;
	len = 0;

	while ((len = read(process.stderr.fileno, &buf[0], buf.length)) == buf.length)
	{
		logTrace("Stderr ...");
		stderr.put(buf[]);
	}
	
	if (len > 0)
	{
		stderr.put(buf[0..len]);
	}

	auto ret = tryWait(process.pid);
	return Ret(ret.status, stdout.data.idup, stderr.data.idup);
}

Json jsonError(string message)
{
	Json result = Json.emptyObject;
	result["error"] = message;

	return result;
}