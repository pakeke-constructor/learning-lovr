
import re
import time
import subprocess
import pyperclip
from _ex6.provider_openai import invoke_llm as invoke_llm_openai
from _ex6.models import M
from _ex6.agents import auto_setup
from _ex6.agents_sound import make_sound_agent
from _ex6.tools import read_headers, read_body, glob, search, write_file, edit_file, read_file, edit_file_lines, escalate, bash, explore_agent, CLAUDE_MD, ENV_PROMPT, git_working_tree, add_tool_repetition_guard, bash, powershell
from _ex6.skills import load_skill
from _ex6.lua_coding_style import SYSTEM_PROMPT_CODING_STYLE
from _ex6.web_tools import websearch_agent
from _ex6.love2d_docs.love2d_docs import love2d_docs
from _ex6.lovr_docs.lovr_docs import lovr_docs
from _ex6.provider_openrouter import cache_manually
from _ex6.workspace import sweep_workspace
import _ex6.agents_long_horizon as h
import ex6
from ex6 import Context, Message



SOUND_PROJECT = """
Project: LOVR-learning, a project to learn the basics of LOVR.

<sound_judgement>
- Short, punchy sounds are much better than long sounds.
- Sounds should be crisp and short, soft on the ears.
- Sounds should be light and quick; 1 sound should never dominate the scene.
- Ensure the sound isn't too overbearing and repetitive.
- Ensure the sound is clear, smooth, and juicy.
- (Most importantly: Ensure that the sound matches what is happening.)
</sound_judgement>
"""

SFX_TOOL_COMPLETE = "<system-reminder>The sound should have been placed in `assets/sfx/_staging/*`. Your job is to move it to a more appropriate spot (and fix its `Asset:` path in CREDITS.txt).</system-reminder>"

def find_sound_effect(ctx: ex6.Context, query: str):
    """
    Example usage: `find_sound_effect("Light Sword-slash or dagger-swipe sound")`

    The agent will try different sounds, listen to them, and will put its chosen sound inside of `assets/sfx/_staging/*`.
    Your job will be to move it to a more appropriate spot.
    """
    sfx_agent = make_sound_agent(
        ctx.app,
        SOUND_PROJECT,
        sfx_dir="assets/sfx/_staging",
        name=f"sound_{int(time.time() * 1000)}",
        cwd=ctx.cwd,
        yolo=ctx.yolo,
    )
    sfx_agent.parent = ctx.name
    if ctx.app.tui:
        ctx.app.tui.add_context(sfx_agent)

    sfx_agent.invoke(query)
    while sfx_agent.llm_is_running: # invoke is async (runs on a thread)
        time.sleep(0.05)
    if sfx_agent.llm_result and sfx_agent.llm_result.error:
        raise RuntimeError(f"Sound agent failed: {sfx_agent.llm_result.error}")
    messages = sfx_agent.get_messages()
    if messages and messages[-1].content:
        return messages[-1].content + "\n\n" + SFX_TOOL_COMPLETE
    raise ValueError("Sound agent didn't return anything... check git tree?")





@ex6.command
def horizon(tui, tasks_path: str = "_notes/_HORIZON_TASKS.md"):
    """Run unattended tasks from a markdown task file."""
    agents = h.default_agents(tui.app)
    agents["main"] = agents["main"].with_tools([find_sound_effect, lovr_docs])
    h.run_horizon(tui.app, tasks_path, agents)



def setup(app: ex6.App):
    sweep_workspace(app)
    auto_setup(app, [find_sound_effect, lovr_docs])



