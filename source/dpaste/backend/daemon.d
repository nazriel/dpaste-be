module dpaste.backend.daemon;

import vibe.data.json: Json, JSONException;
import vibe.core.log: logTrace, logWarn, logInfo, logError, logFatal;

import dpaste.backend.common;

void getAvailableUsers(const ref Json json, ref User[uint] users) @system nothrow
{
	import std.conv: to;
	
	try 
	{
		assert("users" in json);

		foreach (cfg; json["users"])
		{
			uint userId = cfg["id"].get!uint;

			uint groupId = 0;
			if ("groupId" in cfg)
			{	
				groupId = cfg["groupId"].get!uint;
			}
			else
			{
				groupId = json["defaultUserGroupId"].get!uint;
			}

			users[ userId ] = User(
				cfg["homePath"].get!string, 
				cfg["name"].get!string,
				userId,
				groupId,
				cfg["permission"].get!string.to!(User.Permissions)
			);
		}
	}
	catch (Exception e)
	{
		logWarn("Got JSON exception while tranversing Users array in JSON config: %s", e.msg);
	}
}

void monitorConfigChanges(string configFilePath) @system nothrow
{
	import core.time: seconds, minutes;
	import std.path: dirName;

	import vibe.core.core: sleep, DirectoryWatcher, watchDirectory, DirectoryChange, DirectoryChangeType;

	DirectoryWatcher dw;
	try 
	{
		dw = watchDirectory(configFilePath.dirName(), false);
	}
	catch (Exception e)
	{
		logFatal("Couldn't setup directory watcher for '%s'. Got exception: %s", configFilePath.dirName(), e.msg);
		gIsRunning = false;

		return;
	}

	logTrace("Starting monitor for config changes");
	
	while (gIsRunning)
	{
		try
		{
			logTrace("Config check iteration");
			
			DirectoryChange[] directoriesChanges;
			dw.readChanges(directoriesChanges, 3.seconds);
			
			foreach (DirectoryChange dc; directoriesChanges)
			{
				if (dc.path.toString() == configFilePath)
				{
					logInfo("Got changes in configuration file. Reloading configuration and users...");
					Json json;
					if (!readConfigFile(configFilePath, json))
					{
						logError(
							"Failed to read new configuration file. "
							"Make sure it has valid format. "
							"Will keep old configuration"
						);
					}
					else
					{
						logTrace("Old configuration content: %s", gConfiguration.toString());
						logTrace("New config content: %s", json.toString());
						
						getAvailableUsers(json, gAvailableUsers);
						gConfiguration = json;
						
					}
				}
			}
			
			vibe.core.core.sleep(5.minutes);
		}
		catch (Exception e)
		{
			logWarn("Got exception while doing ConfigCheck roundup: %s", e.msg);
		}
	}
}

User findFreeSlot(
	const ref User[uint] availableUsers, 
	const ref User[uint] activeUsers, 
	User.Permissions permissionLevel) @safe nothrow
{
	import std.conv: to;
	
	User result = User.init;

	try // opApply may throw...?
	{
		foreach (user; availableUsers)
		{
			if (user.permission == permissionLevel)
			{
				if (user.id !in activeUsers)
				{
					logTrace("Found free spot: %s [ %d ]", user.name, user.id);
					result = user;
				}
			}
		}
	}
	catch (Exception e)
	{
		logWarn("Got exception while looking for free user's spot: %s", e.msg);
	}
	
	if (result == User.init)
	{
		logInfo("No free available users for permission '%s' level", permissionLevel.to!string);
	}
	
	return result;
}

bool reserveSlot(const ref User user, ref User[uint] activeUsers) @safe nothrow
{
	if (user.id in activeUsers)
	{
		logWarn("Specified user is already reserved and used by application. Internal error?");
		return false;
	}
	
	logTrace("Reserving spot in activeUsers for user: %s [ %d ]", user.name, user.id);
	
	activeUsers[user.id] = user;
	
	return true;
}

bool freeSlot(const ref User user, ref User[uint] activeUsers) @safe nothrow
{
	if (user.id !in activeUsers)
	{
		logWarn("Specified user wasn't reserved. Internal error?");
		return false;
	}
	
	logTrace("Releasing spot for user: %s [ %d ]", user.name, user.id);
	
	return activeUsers.remove(user.id);
}