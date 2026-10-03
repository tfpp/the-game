# Phases

## Summary

The deliverables of this game will be completed in multiple phases. Read through each phase to understand what you need to accomplish at each step. It's important to not jump ahead and implement a new phase for which the previous phase has not been completed. Features or systems often depend on each other so make sure to check for any previous work that has not been implemented.

## Phase 0

This phase is focused on creating the development environment and a basic example of gameplay

### Project setup

- [x] Basic project setup
- [x] Project compiles

### Game Deployment

- [x] Deploys to the project Github Pages instance on merge to `main`

### Harness

- [x] Supports Claude
- [x] Supports Codex

### Discord Bot

- [x] Integrates with Discord to allow users to submit issues and make features
- [x] Asks the user for approval before merging

### Game

- [x] Basic movement controller 
- [x] Multiplayer networking
- [x] Elevators with multiple zones
- [x] Rooms to explore
- [x] Basic casino
- [x] Very basic guns and combat


## Phase 1

This phase is focused on developing a fun gameplay loop that keeps people interested

### Elevator

- [ ] Elevator is joinable by up to 4 people
- [ ] When more than 4 players are in the elevator a weight limit indicator light turns on and the doors will refuse to close
- [x] When the hall call button is pressed the door opens and players are free to enter (completed in phase 0)
- [ ] The elevator takes the occupants to a random instanced zone of the slums together. They will all be in the same instance of the slum zone and see eachother, but other groups will not encounter eachother. For example Group 1 and Group 2 can both be in the parking garage at the same time but they cannot see nor affect eachother.

### Instanced Room Controller

- [ ] Some zones are shared and are not instanced. The casino areas are shared zones and are not instanced these hubs should be accessible to everyone on the server. Other doors accessible within the casino should also be shared such as the gnome doors and stuff.
- [ ] Other zones are instanced and should only be accessible to players who enter into the zone together in the elevator. The only instanced zones are the slums right now.
- [ ] Only the active zone that the player is in is loaded. This is important to save on resources. Currently if the player noclips they are in the same scene as the rest of the casino which is not desired.
- [ ] Each zone is a separate Godot scene
- [ ] Network updates for players are only sent to the players within that scene/zone
- [ ] Chat messages can be global between all zones

### Parking Garage Zone

- [ ] Develop the parking garage zone 
- [ ] Add 1 class of enemy
- [ ] Spawn enemies around the zone randomly but at pre-placed map locations
- [ ] Improve the layout of the map to make it fun and compelling
- [ ] Tune the difficulty to keep players on their feet

### Basic Loot System

- [x] Convert loot value to the player's money through the existing pawn counter (retain selling rather than replace the shipped loop; Phase 1 C1, #430).
- [x] Create 5 types of loot. The rarer the more valuable but harder and less likely to find, the more common the cheaper but more plentiful
- [ ] When the user interacts with a loot item it shows a message on the screen "Pickup <item_name> ($<Item_value>)"