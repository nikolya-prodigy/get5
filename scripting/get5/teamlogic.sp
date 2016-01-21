public void EnforceClientTeams() {
    LogDebug("EnforceClientTeams");
    for (int i = 1; i <= MaxClients; i++) {
        if (IsAuthedPlayer(i)) {
            EnforceTeam(i);
        }
    }
}

public void EnforceCoachTeams() {
    LogDebug("EnforceCoachTeams");
    for (int i = 1; i <= MaxClients; i++) {
        if (IsAuthedPlayer(i) && IsClientCoaching(i)) {
            MoveClientToCoach(i);
        }
    }
}

public void EnforceTeam(int client) {
    LogDebug("EnforceTeam %L", client);
    MatchTeam correctTeam = GetClientMatchTeam(client);
    int csTeam = MatchTeamToCSTeam(correctTeam);

    if (GetClientTeam(client) != csTeam) {
        if (IsClientCoaching(client)) {
            UpdateCoachTarget(client, csTeam);
        } else {
            if (CountPlayersOnCSTeam(csTeam) >= g_PlayersPerTeam) {
                MoveClientToCoach(client);
            } else {
                SwitchPlayerTeam(client, csTeam);
            }
        }
    }
}

public Action Command_JoinGame(int client, const char[] command, int argc) {
    if (g_GameState == GameState_None) {
        return Plugin_Continue;
    }
    EnforceTeam(client);
    return Plugin_Continue;
}

public Action Command_JoinTeam(int client, const char[] command, int argc) {
    // Don't do anything if not live/not in startup phase.
    if (g_GameState == GameState_None) {
        return Plugin_Continue;
    }

    return Plugin_Stop;
}

public void MoveClientToCoach(int client) {
    MatchTeam matchTeam = GetClientMatchTeam(client);
    if (matchTeam != MatchTeam_Team1 && matchTeam != MatchTeam_Team2) {
        return;
    }

    int csTeam = MatchTeamToCSTeam(matchTeam);
    char teamString[4];
    CSTeamString(csTeam, teamString, sizeof(teamString));

    // If we're in warmup or a freezetime we use the in-game
    // coaching command. Otherwise we manually move them to spec
    // and set the coaching target.
    if (!InWarmup() && !InFreezeTime()) {
        SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
        UpdateCoachTarget(client, csTeam);
    } else {
        g_MovingClientToCoach[client] = true;
        FakeClientCommand(client, "coach %s", teamString);
        g_MovingClientToCoach[client] = false;
    }
}

public Action Command_SmCoach(int client, int args) {
    MoveClientToCoach(client);
    return Plugin_Handled;
}

public Action Command_Coach(int client, const char[] command, int argc) {
    if (!IsAuthedPlayer(client)) {
        return Plugin_Stop;
    }

    if (InHalftimePhase()) {
        return Plugin_Stop;
    }

    if (g_MovingClientToCoach[client]) {
        return Plugin_Continue;
    }

    // TODO: add a way to leave the coach spot
    MoveClientToCoach(client);
    return Plugin_Stop;
}

public MatchTeam GetClientMatchTeam(int client) {
    char auth[AUTH_LENGTH];
    GetClientAuthId(client, AUTH_METHOD, auth, sizeof(auth));
    return GetAuthMatchTeam(auth);
}

public int MatchTeamToCSTeam(MatchTeam t) {
    if (t == MatchTeam_Team1) {
        return g_TeamSide[MatchTeam_Team1];
    } else if (t == MatchTeam_Team2) {
        return g_TeamSide[MatchTeam_Team2];
    } else if (t == MatchTeam_TeamSpec) {
        return CS_TEAM_SPECTATOR;
    } else {
        return CS_TEAM_NONE;
    }
}

public MatchTeam CSTeamToMatchTeam(int csTeam) {
    if (csTeam == g_TeamSide[MatchTeam_Team1]) {
        return MatchTeam_Team1;
    } else if (csTeam == g_TeamSide[MatchTeam_Team2]) {
        return MatchTeam_Team2;
    } else if (csTeam == CS_TEAM_SPECTATOR) {
        return MatchTeam_TeamSpec;
    } else {
        return MatchTeam_TeamNone;
    }
}

public MatchTeam GetAuthMatchTeam(const char[] auth) {
    for (int i = 0; i < view_as<int>(MatchTeam_Count); i++) {
        MatchTeam team = view_as<MatchTeam>(i);
        if (IsAuthOnTeam(auth, team)) {
            return team;
        }
    }
    return MatchTeam_TeamNone;
}

public int CountPlayersOnCSTeam(int team) {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsAuthedPlayer(i) && GetClientTeam(i) == team) {
            count++;
        }
    }
    return count;
}

public int CountPlayersOnMatchTeam(MatchTeam team) {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsAuthedPlayer(i) && GetClientMatchTeam(i) == team) {
            count++;
        }
    }
    return count;
}

public Action Event_OnPlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    return Plugin_Continue;
}

// Returns the match team a client is the captain of, or MatchTeam_None.
public MatchTeam GetCaptainTeam(int client) {
    if (client == GetTeamCaptain(MatchTeam_Team1)) {
        return MatchTeam_Team1;
    } else if (client == GetTeamCaptain(MatchTeam_Team2)) {
        return MatchTeam_Team2;
    } else {
        return MatchTeam_TeamNone;
    }
}

public int GetTeamCaptain(MatchTeam team) {
    ArrayList auths = GetTeamAuths(team);
    char buffer[AUTH_LENGTH];
    for (int i = 0; i < auths.Length; i++) {
        auths.GetString(i, buffer, sizeof(buffer));
        int client = AuthToClient(buffer);
        if (IsAuthedPlayer(client)) {
            return client;
        }
    }
    return -1;
}

public int GetNextTeamCaptain(int client) {
    if (client == g_VetoCaptains[MatchTeam_Team1]) {
        return g_VetoCaptains[MatchTeam_Team2];
    } else {
        return g_VetoCaptains[MatchTeam_Team1];
    }
}

public ArrayList GetTeamAuths(MatchTeam team) {
    return g_TeamAuths[team];
}

public bool IsAuthOnTeam(const char[] auth, MatchTeam team) {
    return IsAuthInList(auth, GetTeamAuths(team));
}

public bool IsAuthInList(const char[] auth, ArrayList list) {
    char buffer[AUTH_LENGTH];
    for (int i = 0; i < list.Length; i++) {
        list.GetString(i, buffer, sizeof(buffer));
        if (SteamIdsEqual(auth, buffer)) {
            return true;
        }
    }
    return false;
}

public void SetStartingTeams() {
    int mapNumber = GetMapNumber();
    if (mapNumber >= g_MapSides.Length || g_MapSides.Get(mapNumber) == SideChoice_KnifeRound) {
        g_TeamSide[MatchTeam_Team1] = TEAM1_STARTING_SIDE;
        g_TeamSide[MatchTeam_Team2] = TEAM2_STARTING_SIDE;
    } else {
        if (g_MapSides.Get(mapNumber) == SideChoice_Team1CT) {
            g_TeamSide[MatchTeam_Team1] = CS_TEAM_CT;
            g_TeamSide[MatchTeam_Team2] = CS_TEAM_T;
        }  else {
            g_TeamSide[MatchTeam_Team1] = CS_TEAM_T;
            g_TeamSide[MatchTeam_Team2] = CS_TEAM_CT;
        }
    }
}

public void AddMapScore() {
    int currentMapNumber = GetMapNumber();

    g_TeamScoresPerMap.Push(0);
    g_TeamScoresPerMap.Set(
        currentMapNumber,
        CS_GetTeamScore(MatchTeamToCSTeam(MatchTeam_Team1)),
        view_as<int>(MatchTeam_Team1));

    g_TeamScoresPerMap.Set(
        currentMapNumber,
        CS_GetTeamScore(MatchTeamToCSTeam(MatchTeam_Team2)),
        view_as<int>(MatchTeam_Team2));
}

public int GetMapScore(int mapNumber, MatchTeam team) {
    return g_TeamScoresPerMap.Get(mapNumber, view_as<int>(team));
}

public int GetMapNumber() {
    return g_TeamMapScores[MatchTeam_Team1] + g_TeamMapScores[MatchTeam_Team2];
}
