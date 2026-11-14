#!/usr/bin/env python3
"""Draws the theme's control icons (#498): slider grabber, switch on/off, dropdown arrow.
Deterministic (no randomness). Palette = main_theme.tres: ink 3B2A20, mid 785F50, cream F3E6CC, accent C8743A.
Run: python3 tools/make_ui_controls.py   (then re-import in Godot)"""
from PIL import Image, ImageDraw
import os
INK=(59,42,32); MID=(120,99,80); CREAM=(243,230,204); ACCENT=(200,116,58); FADE=(221,208,185)
S=8  # supersample
out=os.path.join(os.path.dirname(__file__),"..","assets","made","ui")
def save(img,name,w,h):
    img.resize((w,h),Image.LANCZOS).save(os.path.join(out,name))
def pill(name,w,h,track,knob_right,border,knob,knob_border):
    im=Image.new("RGBA",(w*S,h*S),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.rounded_rectangle([0,0,w*S-1,h*S-1],radius=h*S//2,fill=border)
    b=2*S
    d.rounded_rectangle([b,b,w*S-1-b,h*S-1-b],radius=(h*S)//2-b,fill=track)
    r=(h*S)//2-5*S//2
    cx=(w*S-h*S//2) if knob_right else h*S//2
    d.ellipse([cx-r-S//2,h*S//2-r-S//2,cx+r+S//2,h*S//2+r+S//2],fill=knob_border)
    d.ellipse([cx-r+S,h*S//2-r+S,cx+r-S,h*S//2+r-S],fill=knob)
    save(im,name,w,h)
pill("switch_off.png",46,26,MID,False,INK,CREAM,INK)
pill("switch_on.png",46,26,ACCENT,True,INK,CREAM,INK)
pill("switch_off_disabled.png",46,26,FADE,False,MID,CREAM,MID)
pill("switch_on_disabled.png",46,26,(222,184,150),True,MID,CREAM,MID)
def knob(name,fill,edge,size=24):
    im=Image.new("RGBA",(size*S,size*S),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.ellipse([S,S,size*S-S-1,size*S-S-1],fill=edge)
    d.ellipse([S+2*S,S+2*S,size*S-S-1-2*S,size*S-S-1-2*S],fill=fill)
    save(im,name,size,size)
knob("slider_grabber.png",CREAM,INK)
knob("slider_grabber_hover.png",(232,160,104),INK)
knob("slider_grabber_disabled.png",FADE,MID)
def arrow(name,col,w=16,h=16):
    im=Image.new("RGBA",(w*S,h*S),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.polygon([(3*S,5*S),(w*S-3*S,5*S),(w*S//2,11*S)],fill=col)
    save(im,name,w,h)
arrow("arrow_down.png",INK); arrow("arrow_down_disabled.png",(160,140,118))
def radio(name,on,w=16,h=16):
    im=Image.new("RGBA",(w*S,h*S),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.ellipse([2*S,2*S,w*S-2*S-1,h*S-2*S-1],fill=INK if on else MID)
    d.ellipse([3*S+S//2,3*S+S//2,w*S-3*S-S//2-1,h*S-3*S-S//2-1],fill=CREAM)
    if on: d.ellipse([5*S,5*S,w*S-5*S-1,h*S-5*S-1],fill=ACCENT)
    save(im,name,w,h)
radio("radio_on.png",True); radio("radio_off.png",False)
