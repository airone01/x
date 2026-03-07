import React, { useState, useEffect } from 'react';

interface Cell {
    content: string;
    classes: string;
}

let next = 1;
const fakeRandom = () => {
    next = next * 1103515243 + 12345;
    const out = (next / 65536) % 32768;
    console.log(out);
    return out;
}

const GridAnimation = ({ class: className }: { class?: string }) => {
    const [grid, setGrid] = useState<Cell[]>([]);
    const rows = 40;
    const cols = 60;
    const totalCells = rows * cols;
    const starProbability = 0.02;
    // const newDropProbability = 0.001;
    const newDropProbability = 0.1;
    const bigStarProbability = 0.2;
    const raindropColor = 'text-blue-300/40';
    const starColor = 'text-yellow-200';
    const rainDropClass = 'raindrop';
    const rainDropHeadClass = 'raindrop-head';
    const refreshMs = 50;

    // Static stars
    const staticMarkers = new Set<number>();
    for (let i = 0; i < totalCells; i++) {
        if (fakeRandom() < starProbability) {
            staticMarkers.add(i);
        }
    }

    const getStar = (index: number) => {
        return fakeRandom() < bigStarProbability ? '。' : '.';
    }

    useEffect(() => {
        // Initialize grid with static markers
        const initialGrid: Cell[] = Array(totalCells).fill(null).map((_, index) => {
            return staticMarkers.has(index)
                ? { content: getStar(index), classes: starColor }
                : { content: '', classes: '' };
        });

        setGrid(initialGrid);

        const interval = setInterval(() => {
            setGrid(prevGrid => {
                const newGrid: Cell[] = Array(totalCells).fill(null).map((_, index) => {
                    return staticMarkers.has(index)
                        ? { content: getStar(index), classes: starColor }
                        : { content: '', classes: '' };
                });

                const occupiedPositions = new Set<number>();

                // Process existing raindrops
                prevGrid.forEach((cell, index) => {
                    if (cell.content === '|' && cell.classes === rainDropHeadClass) {
                        const nextIndex = index + cols;
                        const canMove = nextIndex < totalCells; // Remove static marker check

                        // Leave trail at current position
                        if (!occupiedPositions.has(index)) {
                            newGrid[index] = {
                                content: '|',
                                classes: rainDropClass
                            };
                            occupiedPositions.add(index);
                        }

                        if (canMove) {
                            if (!occupiedPositions.has(nextIndex)) {
                                // Override star position with raindrop
                                newGrid[nextIndex] = {
                                    content: '|',
                                    classes: rainDropHeadClass
                                };
                                occupiedPositions.add(nextIndex);
                            }
                        } else {
                            // Respawn logic (unchanged)
                            const col = index % cols;
                            const topIndex = col;
                            if (!staticMarkers.has(topIndex) && Math.random() < newDropProbability) {
                                newGrid[topIndex] = {
                                    content: '|',
                                    classes: rainDropHeadClass
                                };
                            }
                        }
                    }
                });

                // Spawn new drops at top
                for (let col = 0; col < cols; col++) {
                    const index = col;
                    if (
                        !staticMarkers.has(index) &&
                        !occupiedPositions.has(index) &&
                        Math.random() < newDropProbability
                    ) {
                        newGrid[index] = {
                            content: '|',
                            classes: rainDropHeadClass
                        };
                    }
                }

                return newGrid;
            });
        }, refreshMs);

        return () => clearInterval(interval);
    }, []);

    return (
        <div className={`w-full h-full p-4 ${className}`}>
            <div
                className={`w-full h-full grid ${raindropColor}`}
                style={{
                    gridTemplateColumns: `repeat(${cols}, 1fr)`,
                    gridTemplateRows: `repeat(${rows}, 1fr)`
                }}
            >
                {grid.map((cell, index) => (
                    <span
                        key={index}
                        className={`flex items-center justify-center font-mono text-sm transition-colors duration-300 ${cell.classes}`}
                    >
                        {cell.content}
                    </span>
                ))}
            </div>
        </div>
    );
};

export default GridAnimation;