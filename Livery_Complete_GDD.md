**LIVERY\
Complete Game Design Document\
Version 1.0**

# Vision Statement

Livery is a wholesome horse care and stable management game inspired by
the bond between horse and rider. The project is being developed for Liv
and focuses on emotional attachment, horse ownership, progression,
competitions and stable growth.

# Project Pillars

1\. Care before competition. 2. Emotional attachment to horses. 3.
Relaxing gameplay. 4. Small scope and finishable milestones. 5.
Expandable architecture.

# Technical Decisions

Godot 4.7 using Compatibility Renderer initially. Forward+ will be
considered when better hardware is available. Blender will be the
primary content creation tool. Assets exported as GLB.

# Core Gameplay Loop

Check horses, feed, groom, clean stalls, train, ride, compete, earn
money, expand stable and acquire horses.

# Horse Systems

Every horse tracks Hunger, Health, Happiness, Trust, Cleanliness, Energy
and Fitness. Each horse also has unique personality and performance
attributes.

# Training System

Training improves speed, stamina, jumping and obedience. Overtraining
reduces energy and happiness.

# Competitions

Initial MVP contains a single competition. Future expansion includes
show jumping, dressage, cross-country and timed events.

# Stable Progression

Player starts with one horse and a small stable. Reputation and income
unlock arenas, breeding facilities, decorations and additional stables.

# Economy

Money comes from competitions, horse sales and stable activities.
Spending includes feed, tack, upgrades and new horses.

# Breeding Roadmap

Breeding is a post-MVP feature. Genetics influence appearance,
temperament and performance. Foals grow into adult horses.

# Animation Strategy

Rigging and animation are created in Blender. Godot handles state
machines and animation blending. Rider and horse remain separate rigs
connected through attachment points for saddle, reins and stirrups.

# Asset Pipeline

Use Blender MCP and AI agents to automate importing, cleaning,
separating, optimising and exporting assets. AI is used as a multiplier,
not as a replacement for game design.

# AI Workflow

Preferred use of AI is generating tools, editor scripts, Blender
automation, documentation and prototyping systems. Design decisions
remain human-led.

# MVP Features

One horse, one stable, feeding, grooming, riding, horse stats,
save/load, one competition, money system and purchasing supplies.

# Features Excluded From MVP

Multiplayer, online systems, advanced breeding, auctions, seasons and
large open worlds.

# Development Roadmap

Phase 1: Horse care foundations. Phase 2: Riding and animation. Phase 3:
Competition gameplay. Phase 4: Economy and progression. Phase 5: Stable
expansion. Phase 6: Future systems.

# Biggest Risk

Scope creep. Finish one small complete game before adding more horses,
events or systems.

# Success Criteria

Liv enjoys the game, players form attachments to horses, gameplay feels
rewarding and the architecture supports future expansion.


Livery
Game Design Document (GDD)
Version 0.1
Vision Statement
Livery is a wholesome horse care and stable management game designed primarily for younger players.

The game aims to create an emotional connection between player and horse through care, training, progression, and competition.

The project is inspired by horse ownership, riding schools, and livery yards, while incorporating modern life-simulation elements.

The long-term goal is to create a relaxing experience where players build a successful stable, develop relationships with their horses, and compete in equestrian events.

Title
Livery
The title contains a hidden reference to Liv.

Possible branding:

LIVery
Livery
The logo should subtly highlight "Liv" while still reading as "Livery".

This creates a personal connection without making it obvious to all players.

Project Goals
The game should:

Be relaxing rather than stressful.
Encourage long-term horse ownership.
Create emotional attachment to horses.
Reward care and dedication.
Be suitable for younger players.
Avoid heavy punishment mechanics.
Be expandable over time.
Target Audience
Primary Audience:

Children and teenagers interested in horses.
Casual life simulation players.
Secondary Audience:

Horse enthusiasts.
Animal care game players.
Family-friendly gaming communities.
Technical Constraints
Engine
Godot 4.7

Renderer
Compatibility Renderer

Reasoning
Current development hardware is limited.

Using Compatibility Renderer allows:

Faster development.
Better performance on lower-end systems.
Easier testing.
Future versions may migrate to:

Forward+
once hardware permits.

Art Direction
Style
Low-poly stylised realism.

Target characteristics:

Bright colours.
Friendly atmosphere.
Realistic proportions.
Soft lighting.
Optimised performance.
Examples:

My Time at Portia
Stardew Valley
Horse Riding Tales
Star Stable
Core Gameplay Loop
The player:

Checks their horses.
Feeds horses.
Grooms horses.
Cleans stables.
Trains horses.
Completes daily tasks.
Enters competitions.
Earns rewards.
Purchases upgrades.
Expands their stable.
Loop repeats with increasing progression.

Player Experience
The player should feel:

Responsible.
Rewarded.
Attached to their horses.
Excited to unlock new content.
Proud of their stable.
The game should create stories naturally through horse progression.

Horse Management
Each horse owns its own set of stats.

Basic Needs
Hunger
Represents feeding requirements.

Cleanliness
Determines horse comfort and happiness.

Energy
Used for training and competitions.

Happiness
General wellbeing.

Trust
Relationship with the player.

Health
Impacts overall performance.

Horse Attributes
Each horse can have unique traits.

Physical Stats
Speed
Stamina
Jumping
Agility
Personality Stats
Temperament
Confidence
Obedience
Friendliness
This ensures every horse feels unique.

Daily Care Activities
Feeding
Increases:

Hunger satisfaction
Health
Grooming
Increases:

Happiness
Trust
Cleaning Stables
Maintains:

Horse health
Stable quality
Training
Increases:

Skills
Competition performance
Consumes:

Energy
Riding
The player can ride horses around the property.

Basic systems:

Walk
Trot
Canter
Gallop
Additional systems may include:

Jumping
Trail rides
Arena work
Competitions
Initial Events
Show Jumping
Navigate obstacle courses.

Timed Racing
Simple speed events.

Dressage
Pattern and precision riding.

Competition Rewards
Players earn:

Money
Trophies
Reputation
Unlockables
Stable Progression
Players begin with a small property.

Starting Facilities
Small stable
One horse
Basic arena
Future Expansions
Additional stables
Indoor arena
Outdoor arena
Breeding facilities
Training grounds
Competition facilities
Economy
Players can earn money by:

Competing
Selling horses
Completing tasks
Breeding horses
Reputation rewards
Money is spent on:

Feed
Equipment
Stable upgrades
Decorations
New horses
Horse Marketplace
Players can:

Buy Horses
Expand their stable.

Sell Horses
Generate income.

Browse Listings
Search for specific traits.

Breeding System (Future Feature)
Not required for Version 1.

Long-term feature.

Breeding Goals
Create unique horses.

Genetics influence:

Coat colours
Markings
Size
Speed
Stamina
Temperament
Foals
Foals can:

Grow over time.
Be trained.
Be sold.
Become competition horses.
Stable Reputation System
The player operates a livery yard.

Reputation increases through:

Happy horses.
Competition wins.
Stable quality.
Customer satisfaction.
Higher reputation unlocks:

Rare horses.
Better events.
Premium equipment.
Animation Pipeline
Decision
Animations should be created in Blender.

Godot should handle:

Animation playback.
Animation trees.
State machines.
Transitions.
Why Blender?
Blender provides:

Better rigging tools.
Weight painting.
Constraint systems.
Easier animation editing.
Godot is better used for implementation rather than animation creation.

Horse and Rider Setup
Horse
Fully rigged model.

Rider
Separate rigged character.

Attachment System
The rider attaches to:

Saddle
Stirrups
Reins
Using attachment points (sockets).

Benefits:

Easier animation management.
Reusable rider system.
Modular equipment.
Asset Pipeline
Workflow
1. Acquire Source Assets
Free models.

2. Import Into Blender
Clean and organise.

3. Separate Components
Examples:

Trees
Rocks
Fences
Buildings
4. Optimise
Reduce complexity.

5. Rig
Where required.

6. Export
GLB format.

7. Import Into Godot
Build gameplay systems.

AI-Assisted Development
AI should be used to:

Build tooling.
Write scripts.
Manage workflows.
Automate Blender tasks.
Generate ideas.
Create documentation.
AI should not be relied upon to design the game.

Game design decisions remain human-driven.

Blender MCP Strategy
Long-term plan:

Use an AI agent to control Blender through MCP.

Tasks:

Batch imports.
Model clean-up.
Asset optimisation.
Rigging assistance.
Export automation.
This can dramatically reduce content creation time.

MVP (Minimum Viable Product)
Version 1.0 should contain:

Horse Care
Feeding
Grooming
Stats
Stable
One stable area
One horse
Riding
Basic movement
Economy
Earn money
Spend money
Competition
One competition
Persistence
Save and load
Version 1 Exclusions
Do NOT build initially:

Multiplayer
Online services
Massive open worlds
Genetics
Complex breeding
Auctions
Advanced AI horses
Seasons system
These can be added later.

Biggest Project Risk
Scope Creep
Previous projects were abandoned because the scope became too large.

Rule:

Build One Complete Feature Before Starting Another
Examples:

Do not build:

50 horses
Build:

1 horse
Do not build:

20 competitions
Build:

1 competition
Do not build:

An entire county
Build:

One stable yard
Development Philosophy
Finish before expanding.

A small finished game is worth more than a huge unfinished game.

Every new feature must improve the core gameplay loop.

If a feature does not make caring for horses more enjoyable, it can wait until later.

Success Criteria
The game is successful when:

Liv enjoys playing it.
The player becomes attached to their horse.
Daily care feels rewarding.
Progression is satisfying.
The game can be expanded without major redesigns.
Ultimately, Livery should feel like owning and caring for a horse rather than simply managing statistics.