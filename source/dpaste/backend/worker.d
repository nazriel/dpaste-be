module dpaste.backend.worker;

// todo: clean up imports
import vibe.http.common;
import vibe.http.server;
import vibe.stream.operations;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;

import std.conv: to;
import std.array: Appender, appender;
import std.process;
import std.stdio;
import std.typecons;

import core.time: seconds, Duration;

import dpaste.backend.daemon;

private Json runWorker(Json request) @system //nothrow
{
	Json response;

	//try
	{
		import dpaste.backend.common;
	
		User.Permissions permission;
		logTrace("Request format in raw JSON: %s", request.toPrettyString());
		
		if ("permission" !in request)
		{
			logWarn("No permission level supplied in request, defaulting to 'guest'");
			permission = User.Permissions.guest;
		}
		else
		{
			try
			{
				permission = request["permission"].get!(string)().to!(User.Permissions);
			}
			catch (JSONException e)
			{
				logError("Failed to convert requested permission level to Permissions type");
			}
		}
		
		User user;
		uint tries = 0;
		while (tries++ < 3)
		{
			user = findFreeSlot(gAvailableUsers, gActiveUsers, permission);
			
			if (user != User.init)
			{
				reserveSlot(user, gActiveUsers);
				break;
			}
			else
			{
				logTrace(
					"No free users for %s permission... waiting %d seconds so far", 
					permission.to!string,
					tries * 3
				);
				sleep(3.seconds);
			}
			
			if (tries >= 2)
			{
				logError("No free users available for 10 seconds! Make sure everything is OKish...");
				return Json.emptyObject;
			}
		}
		
		scope(exit)
		{
			freeSlot(user, gActiveUsers);
		}
		
		string workerBinary = gConfiguration["misc"]["workerBinary"].get!string;
				
		Duration compilationTimeout;
		Duration runtimeTimeout;
		
		with(User.Permissions) switch (permission)
		{
			default:
			case guest:
				runtimeTimeout = compilationTimeout = 5.seconds;
				break;
			case registered:
				runtimeTimeout = compilationTimeout = 10.seconds;
				break;
			case dlang:
				runtimeTimeout = compilationTimeout = 15.seconds;
				break;
		}

		response = Json.emptyObject;
		response["compilation"] = Json.emptyObject;
		response["runtime"] = Json.emptyObject;

		auto arguments = [
			workerBinary, 
			"--userId=" ~ user.id.to!string,
			"--groupId=" ~ user.groupId.to!string,
			"--userName=" ~ user.name,
			"--homePath=" ~ user.homePath,
			"--permission=" ~ permission.to!string,
			"--timeout=" ~ compilationTimeout.total!"seconds".to!string,
			"--mode=compilation"
		];
		logTrace("Spawning worker binary for compilation: '%s' with arguments: %s", workerBinary, arguments);
		auto pipe = pipeProcess(arguments);

		try 
		{
			logTrace(
				"Processing compilation output, while providing following input: %s", 
				request["compilation"].toString()
			);

			auto result = processInputOutput(
				pipe, 
				request["compilation"].toString(), 
				compilationTimeout
			);
			logTrace("Compilation result: %s", result);

			response["compilation"] = result.stdout.parseJsonString();

			if ("status" !in response["compilation"])
			{
				logError("Malformed response from Worker. Got: %s", response["compilation"].toPrettyString());
				response["compilation"]["status"] = -1;
			}
		}
		catch (JSONException e)
		{
			logError("Got exception while parsing output of compilation: %s (%s: %d)", e.msg, e.file, e.line);
			response["compilation"]["status"] = -1;
		}
		
		// If compilation failed for any reason, return what've got so far
		if (response["compilation"]["status"].get!int != 0)
		{
			logTrace("Compilation failed with '%d' status - we will return now.", response["compilation"]["status"].get!int);
			return response;
		}

		arguments = [
			workerBinary, 
			"--userId=" ~ user.id.to!string,
			"--groupId=" ~ user.groupId.to!string,
			"--userName=" ~ user.name,
			"--homePath=" ~ user.homePath,
			"--permission=" ~ permission.to!string,
			"--timeout=" ~ runtimeTimeout.total!"seconds".to!string,
			"--mode=runtime"
		];
		logTrace("Spawning worker binary for runtime: '%s' with arguments: %s", workerBinary, arguments);
		pipe = pipeProcess(arguments);
		
		try 
		{
			logTrace("Processing runtime output, while providing following input: %s", request["runtime"].toString());
			auto result = processInputOutput(
				pipe, 
				request["runtime"].toString(), 
				runtimeTimeout);
			logTrace("Runtime result: %s", result);

			response["runtime"] = result.stdout.parseJsonString();

			if ("status" !in response["runtime"])
			{
				logError("Malformed response from Worker. Got: %s", response["runtime"].toPrettyString());
				response["runtime"]["status"] = -1;
			}
		}
		catch (JSONException e)
		{
			logError("Got exception while parsing output of runtime: %s (%s: %d)", e.msg, e.file, e.line);
			response["runtime"]["status"] = -1;
		}
	}
	//catch (Exception e)
	{
	//	logError("Got exception while handling request and spawning worker: %s (%s: %d)", e.msg, e.file, e.line);
	}

	return response;
}

void spawnWorker(HTTPServerRequest req, HTTPServerResponse res)
{
	Json result = runWorker(req.json);
	logTrace("Sending following response to the client: %s", result.toString());
	res.writeJsonBody(result);
}
