"""
Test vision extraction in real-time while playing the game.

Shows the debug overlay alongside the game screen so you can see
what the VisionExtractor is detecting frame-by-frame.

Usage:
    python RL_based_submission/test_vision.py --task mathematical_logic/task_1
    python RL_based_submission/test_vision.py --task mathematical_logic/task_2
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pygame

_project_root = str(Path(__file__).resolve().parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

import nesylink
from nesylink.core.constants import (
    TARGET_FPS,
    WINDOW_HEIGHT,
    WINDOW_WIDTH,
)
from nesylink.core.input import HumanInputState
from nesylink.tasks import list_tasks
from RL_based_submission.vision_extractor import (
    VisionExtractor,
    SymbolicFrame,
    DynamicEntity,
    render_debug_overlay,
    WALL, CHEST, TRAP, GAP, ABYSS, BRIDGE,
    BUTTON, BUTTON_PRESSED, SWITCH, SWITCH_PRESSED,
    NPC, FLOOR, UNKNOWN,
)

SCALE = 3  # overlay pixel scale for readability


def _print_detections(symbolic: SymbolicFrame, step: int) -> None:
    """Print a compact summary of what was detected this frame."""
    parts = [f"Step {step:4d}"]

    if symbolic.player is not None:
        p = symbolic.player
        parts.append(f"Player @ tile {p.anchor_tile} px={p.center_px}")
    else:
        parts.append("Player: NOT FOUND")

    parts.append(f"Monsters: {len(symbolic.monsters)}")
    for m in symbolic.monsters:
        parts.append(f"  @ tile {m.anchor_tile} ({m.pixel_count} px)")

    # Count static labels
    static = symbolic.static
    counts = {}
    for row in range(8):
        for col in range(10):
            label = static[row, col]
            counts[label] = counts.get(label, 0) + 1

    parts.append("Static: " + " ".join(
        f"{k}={v}" for k, v in sorted(counts.items()) if v > 0 and k != FLOOR
    ))

    blocked = symbolic.blocked_tiles()
    parts.append(f"Blocked tiles: {len(blocked)}")

    print(" | ".join(parts))


def main() -> None:
    parser = argparse.ArgumentParser(description="Test vision extraction live")
    task_ids = [t.task_id for t in list_tasks()]
    parser.add_argument("--task", type=str, default="mathematical_logic/task_1",
                        choices=task_ids, help=f"Task ID. Available: {task_ids}")
    parser.add_argument("--seed", type=int, default=None, help="Random seed")
    parser.add_argument("--memory", action="store_true", default=True,
                        help="Use memory to fill occluded tiles")
    parser.add_argument("--no-memory", dest="memory", action="store_false",
                        help="Disable memory")
    parser.add_argument("--print-every", type=int, default=1,
                        help="Print detection summary every N steps")
    args = parser.parse_args()

    # Build environment
    env = nesylink.make_env(
        task_id=args.task,
        api="gym",
        render_mode="rgb_array",
        auto_reset_on_step=True,
        observation_mode="pixels",
    )

    obs, info = env.reset(seed=args.seed)
    print(f"\n[Task: {args.task}]")
    print(f"[Controls: Arrows=move, Z=A(sword), X=B(shield), V=toggle overlay, C=print detections, Esc=quit]")
    print(f"[Overlay legend: W=Wall C=Chest TR=Trap G=Gap BR=Bridge BT=Button SW=Switch N=NPC E*=Exit]\n")

    pygame.init()
    pygame.display.set_caption(f"Vision Test 鈥?{args.task}")
    # Double-wide window: game on left, overlay on right
    screen = pygame.display.set_mode((WINDOW_WIDTH * 2 + 20, WINDOW_HEIGHT + 40))
    clock = pygame.time.Clock()
    input_state = HumanInputState()

    vision = VisionExtractor(use_memory=args.memory)
    show_overlay = True
    game_over = False
    victory = False
    running = True
    step_count = 0
    last_symbolic: SymbolicFrame | None = None

    def reset_episode():
        nonlocal obs, info, game_over, victory, step_count
        obs, info = env.reset(seed=args.seed)
        vision.reset()
        step_count = 0
        game_over = False
        victory = False
        print("[Episode reset]\n")

    while running:
        clock.tick(TARGET_FPS)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                elif event.key == pygame.K_v:
                    show_overlay = not show_overlay
                    print(f"[Overlay {'ON' if show_overlay else 'OFF'}]")
                elif event.key == pygame.K_c:
                    if last_symbolic is not None:
                        _print_detections(last_symbolic, step_count)
                elif game_over or victory:
                    reset_episode()
                else:
                    input_state.handle_keydown(event.key)
            elif event.type == pygame.KEYUP:
                input_state.handle_keyup(event.key)

        if running and not game_over and not victory:
            action = input_state.resolve_action()
            obs, reward, terminated, truncated, info = env.step(action)
            step_count += 1

            # Run vision extraction
            try:
                symbolic = vision.extract(obs)
                last_symbolic = symbolic
                if step_count % args.print_every == 0:
                    _print_detections(symbolic, step_count)
            except Exception as exc:
                print(f"[Vision error at step {step_count}: {exc}]")
                last_symbolic = None

            if terminated:
                reason = info.get("terminal_reason")
                if reason == "agent_dead":
                    game_over = True
                    print("[GAME OVER - agent died]")
                elif reason == "world_completed":
                    victory = True
                    print("[VICTORY - world completed!]")

        # 鈹€鈹€ Render 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
        screen.fill((30, 30, 30))

        # Left: game screen
        frame = env.render()
        game_surface = pygame.surfarray.make_surface(np.transpose(frame, (1, 0, 2)))
        game_scaled = pygame.transform.scale(game_surface, (WINDOW_WIDTH, WINDOW_HEIGHT))
        screen.blit(game_scaled, (10, 10))
        _draw_label_on_screen(screen, "GAME", 10, WINDOW_HEIGHT + 15, (200, 200, 200))

        # Right: vision debug overlay
        if show_overlay and last_symbolic is not None:
            try:
                overlay = render_debug_overlay(obs, last_symbolic, extractor=vision, scale=SCALE)
                overlay_h = overlay.shape[0]
                overlay_w = overlay.shape[1]
                overlay_surface = pygame.surfarray.make_surface(
                    np.transpose(overlay, (1, 0, 2))
                )
                # Scale to fit
                target_w = WINDOW_WIDTH
                target_h = int(overlay_h * (WINDOW_WIDTH / overlay_w))
                overlay_scaled = pygame.transform.scale(overlay_surface, (target_w, target_h))
                screen.blit(overlay_scaled, (WINDOW_WIDTH + 20, 10))
                _draw_label_on_screen(screen, "VISION (grid labels + entity boxes)",
                                      WINDOW_WIDTH + 20, WINDOW_HEIGHT + 15, (200, 200, 200))
            except Exception as exc:
                _draw_label_on_screen(screen, f"Overlay error: {exc}",
                                      WINDOW_WIDTH + 20, 30, (255, 100, 100))
        else:
            _draw_label_on_screen(screen, "Overlay OFF (press V)",
                                  WINDOW_WIDTH + 20, WINDOW_HEIGHT // 2, (150, 150, 150))

        # Status bar
        if game_over:
            _draw_label_on_screen(screen, "GAME OVER - Press any key",
                                  10, 10, (255, 80, 80))
        elif victory:
            _draw_label_on_screen(screen, "VICTORY - Press any key",
                                  10, 10, (80, 255, 80))

        pygame.display.flip()

    env.close()
    pygame.quit()


def _draw_label_on_screen(screen, text: str, x: int, y: int, color: tuple[int, int, int]) -> None:
    font = pygame.font.SysFont(None, 18)
    surf = font.render(text, True, color)
    screen.blit(surf, (x, y))


if __name__ == "__main__":
    main()

