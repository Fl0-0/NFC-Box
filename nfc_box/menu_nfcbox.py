#!/usr/bin/env python2

import RPi.GPIO as GPIO
from PIL import Image
from PIL import ImageFont
from PIL import ImageDraw
import os, fnmatch, time
from subprocess import PIPE, Popen
import re
from luma.core.interface.serial import i2c
from luma.oled.device import sh1106

GPIO.setmode(GPIO.BCM)

KEY_LEFT = 5
KEY_RIGHT = 6
KEY_UP = 13
KEY_DOWN = 19
KEY_ENTER = 26

GPIO.setup(KEY_LEFT, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(KEY_RIGHT, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(KEY_UP, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(KEY_DOWN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(KEY_ENTER, GPIO.IN, pull_up_down=GPIO.PUD_UP)

width = 128
height = 64
serial = i2c(port=1, address=0x3C)
device = sh1106(serial)

dumps_dir = '/root/nfc_box/dumps/'
base_dir = '/root/nfc_box/'
image = Image.new('1', (width, height))

draw = ImageDraw.Draw(image)
font = ImageFont.truetype("arial.ttf", 12)


def string_size(fontType,string):
    string_width = 0
    string_height = 0
    for i, c in enumerate(string):
        char_width, char_height = draw.textsize(c, font=fontType)
        string_width += char_width
        if char_height > string_height:
            string_height = char_height
    return {"width": string_width, "height": string_height}

def display_upper(menu, selected):
    text = menu["title"]
    draw.rectangle((0,0,width,height), outline=0, fill=0)
    font14 = ImageFont.truetype("arial.ttf", 14)
    size = string_size(font, text)
    x = (width/2) - (size['width']/2)
    y = 0
    if type(menu["list"][selected]) is dict and menu["list"][selected].has_key("next"):
        draw.text((width-14, y), '>', font=font14, fill=255)
    draw.text((x, y), text, font=font14, fill=255)
    if menu.has_key("previous"):
        draw.text((0, y), '<', font=font14, fill=255)
    draw.line((0, size['height'] + 5, 128, size['height'] + 5), width=2, fill=255)

def display_center(menu_array, selected):
    height = 22
    padding = 14
    first = (selected / 3) * 3
    if ((first + 3) <= len(menu_array)):
        disp_size = 3
    else:
        disp_size = len(menu_array) % 3
    for i in range(first, first+disp_size):
        text = menu_array[i]
        if type(text) is str:
            text = text
        else:
            text = text["text"]
        if i == first and i != 0 and i == selected:
            draw.rectangle((0,height,128,height+padding-2), outline=0, fill=255)
            draw.text((0, height), text, font=font, fill=0)
            draw.text((width-12, height), '^', font=font, fill=0)
        elif i == first+disp_size-1 and i != len(menu_array)-1 and i == selected:
            draw.rectangle((0,height,128,height+padding-2), outline=0, fill=255)
            draw.text((0, height), text, font=font, fill=0)
            draw.text((width-12, height), 'v', font=font, fill=0)
        elif i == selected:
            draw.rectangle((0,height,128,height+padding-2), outline=0, fill=255)
            draw.text((0, height), text, font=font, fill=0)
        elif i == first and i != 0:
            draw.text((0, height), text, font=font, fill=255)
            draw.text((width-12, height), '^', font=font, fill=255)
        elif i == first+disp_size-1 and i != len(menu_array)-1:
            draw.text((0, height), text, font=font, fill=255)
            draw.text((width-12, height), 'v', font=font, fill=255)
        else:
            draw.text((0, height), text, font=font, fill=255)
        height += padding

def default_display(menu, selected):
    if menu.has_key("title") and menu.has_key("list"):
        display_upper(menu, selected)
        display_center(menu["list"], selected)
        device.display(image)

def get_dumps():
    result = []
    tmp_list = fnmatch.filter(os.listdir(dumps_dir), '*.mfd')
    for dump in tmp_list:
        result.append({"text": dump})
    return result

def nfc_write_chinese(dump):
    cmd = "nfc-mfclassic W a u " + dumps_dir + dump
    p = Popen(cmd, stdout=PIPE, stderr=PIPE, shell=True)
    stdout, stderr = p.communicate()
    code = p.wait()
    match = re.search('Done,.*written', stdout)
    if match:
        return 0
    else:
        return -1

def nfc_write_normal(dump):
    cmda = "nfc-mfclassic w A u " + dumps_dir + dump + " " + dumps_dir + dump + " f"
    cmdb = "nfc-mfclassic w B u " + dumps_dir + dump + " " + dumps_dir + dump + " f"
    p = Popen(cmda, stdout=PIPE, stderr=PIPE, shell=True)
    stdout, stderr = p.communicate()
    match = re.search('Done,\s([0-9]+).*written', stdout)
    if match:
        if match.group(1) == "63":
            return 0
        else:
            p = Popen(cmdb, stdout=PIPE, stderr=PIPE, shell=True)
            stdout, stderr = p.communicate()
            match = re.search('Done,\s([0-9]+).*written', stdout)
            if match:
                return 0
            else:
                return -1
    else:
        return -1

def nfc_crack(dump):
    last = 0
    crack_list = fnmatch.filter(os.listdir(dumps_dir), 'dump.[0-9]*.mfd')
    for crack in crack_list:
        tmp = crack.split('.')
        int_tmp = int(tmp[1])
        if int_tmp > last:
            last = int_tmp
    last += 1
    
    cmd = "mfoc -O " + "/tmp/dump." + str(last) + ".mfd"
    p = Popen(cmd, stdout=PIPE, stderr=PIPE, shell=True)
    stdout, stderr = p.communicate()
    code = p.wait()
    match = re.search('Auth with all sectors succeeded, dumping keys to a file', stdout)
    if match:
        cmd= base_dir + "remount-slash.sh rw"
        p = Popen(cmd, stdout=PIPE, stderr=PIPE, shell=True)
        p.wait()

        cmd= "mv /tmp/dump." + str(last) + ".mfd " + dumps_dir + "dump." + str(last) + ".mfd"
        p = Popen(cmd, stdout=PIPE, stderr=PIPE, shell=True)
        p.wait()

        cmd= base_dir + "remount-slash.sh ro"
        p = Popen(cmd, stdout=PIPE, stderr=PIPE, shell=True)
        p.wait()
        
        menu_write["list"] = get_dumps()
        menu_emulate["list"] = get_dumps()
        return 0
    else:
        return -1

selected = 0
dump_list = get_dumps()

menu = {"title": "Menu", "list": [{"text": "Write"}, {"text": "Emulate"}, {"text": "Crack"}]}
menu_emulate = {"title": "Emulate", "list": dump_list, "previous": menu}
#menu_crack = {"title": "Crack", "previous": menu}
menu_write = {"title": "Write", "list": dump_list, "previous": menu}
menu_write_next = {
    "title": "Type",
    "list": [{"text": "Chinese", "action": nfc_write_chinese}, {"text": "Normal", "action": nfc_write_normal}],
    "previous": menu_write}
menu_ok = {"title": "Success", "list": ["", "Good Job!", ""], "previous": menu}
menu_ko = {"title": "Error", "list": ["", "Someting Wrong!", ""], "previous": menu}

menu["list"][0]["next"] = menu_write
menu["list"][1]["next"] = menu_emulate
menu["list"][2]["action"] = nfc_crack
#menu["list"][1]["next"] = menu_crack
for dump in menu_write["list"]:
    dump["next"] = menu_write_next

cur_menu = menu
cur_item = ""

default_display(cur_menu, selected)
#device.display(image)

while True:
    display = "default"

    if not GPIO.input(KEY_UP):
        selected -= 1
        if selected < 0: selected = 0
        default_display(cur_menu, selected)
    elif not GPIO.input (KEY_DOWN):
        selected += 1
        if (selected > (len(cur_menu["list"]) - 1)): selected = len(cur_menu["list"]) - 1
        default_display(cur_menu, selected)
    elif not GPIO.input (KEY_LEFT):
        if cur_menu.has_key("previous"):
            cur_menu = cur_menu["previous"]
            selected = 0
            default_display(cur_menu, selected)
    elif not GPIO.input (KEY_RIGHT):
        if cur_menu.has_key("list") and type(cur_menu["list"][selected]) is dict and cur_menu["list"][selected].has_key("next"):
            cur_item = cur_menu["list"][selected]["text"]
            cur_menu = cur_menu["list"][selected]["next"]
            selected = 0
            default_display(cur_menu, selected)
    elif not GPIO.input(KEY_ENTER):
        if cur_menu.has_key("list") and type(cur_menu["list"][selected]) is dict and cur_menu["list"][selected].has_key("action"):
            ret = cur_menu["list"][selected]["action"](cur_item)
            if ret == 0:
                cur_menu = menu_ok
            else:
                cur_menu = menu_ko
            selected = 1
            default_display(cur_menu, selected)

    #device.display(image)
    time.sleep(0.05)
