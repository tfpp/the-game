# Suicide command

Enter `/suicide` in chat (the existing `/sucide` spelling also works) to die and
automatically respawn. This uses the server-owned Combat lifecycle: the **u died gg**
screen lasts two seconds, self-damage earns no kill, and existing death listeners
apply normal death consequences, including dropping valuables on a slum run.
The server only acts on the peer identity supplied by the chat command dispatcher,
and requires that peer's player to exist. Repeated requests during the death delay
are ignored by Combat. Without Combat loaded, the previous kill-plane rescue remains
the fallback. No new controls or RPCs are added.
