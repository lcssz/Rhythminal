# Rhythminal!

#### 🚀 Play Guitar Hero on your terminal !! 
Rhythminal is a terminal-based rhythm game implemented in Zig, using the [vaxis](https://github.com/rockorager/libvaxis/tree/main) library for terminal manipulation.

## How to play

#### Gameplay Mechanics

-   Notes fall vertically across four columns
-   Players use A, S, J, K keys to hit notes
-   Scoring system with hits and misses tracking
-   Visual feedback for successful hits
-   Customizable game speed and update frequency
-   Press 'Q' to quit the game

## Building and Running the Project

#### Prerequisites

-   Zig compiler (version 0.13.0)
-   Terminal with UTF-8 and color support

#### Build Steps

1.  **Clone the Project**
```bash
git clone https://github.com/lcssz/rhythminal cd rhythminal
```
**Build and run the project**
```bash
zig build && zig-out/bin/rhythminal
```
