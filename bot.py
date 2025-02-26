#!/usr/bin/env python3
# coding: utf-8
# Create by : https://github.com/lidalao/ServerStatus
# 版本：0.0.1, 支持Python版本：2.7 to 3.9
# 支持操作系统： Linux, OSX, FreeBSD, OpenBSD and NetBSD, both 32-bit and 64-bit architectures

import os
import sys
import requests
import time
import traceback

NODE_STATUS_URL = 'http://sss/json/stats.json'
MAX_COUNTER = 100  # 新增：最大计数常量

offs = []
counterOff = {}
counterOn = {}

def _send(text):
    chat_id = os.getenv('TG_CHAT_ID')
    bot_token = os.environ.get('TG_BOT_TOKEN')
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage?parse_mode=HTML&disable_web_page_preview=true&chat_id={chat_id}&text={text}"
    try:
        with requests.get(url, timeout=5) as response:  # 修改：设置超时
            response.raise_for_status()  # 修改：检查请求是否成功
    except Exception as e:
        print("catch exception: ", traceback.format_exc())

def send2tg(srv, flag):
    if srv not in counterOff:
        counterOff[srv] = 0
    if srv not in counterOn:
        counterOn[srv] = 0

    if flag == 1:  # online
        if srv in offs:
            if counterOn[srv] < MAX_COUNTER:  # 修改：调整监控报警频率
                counterOn[srv] += 1
                return
            offs.remove(srv)
            counterOn[srv] = 0
            text = f'<b>Server Status</b>\n主机上线: {srv}'
            _send(text)
    else:  # offline
        if srv not in offs:
            if counterOff[srv] < MAX_COUNTER:  # 修改：调整监控报警频率
                counterOff[srv] += 1
                return
            offs.append(srv)
            counterOff[srv] = 0
            text = f'<b>Server Status</b>\n主机下线: {srv}'
            _send(text)

def sscmd(address):
    while True:
        try:
            with requests.get(url=address, headers={"User-Agent": "ServerStatus/20211116"}, timeout=5) as r:  # 修改：设置超时
                r.raise_for_status()  # 修改：检查请求是否成功
                jsonR = r.json()
        except Exception as e:
            print('未发现任何节点或请求失败:', traceback.format_exc())  # 修改：打印详细错误信息
            time.sleep(3)  # 等待后重试
            continue

        for server in jsonR.get("servers", []):  # 修改：使用 get 方法避免 KeyError
            if not (server["online4"] or server["online6"]):
                send2tg(server["name"], 0)
            else:
                send2tg(server["name"], 1)

        time.sleep(3)

if __name__ == '__main__':
    sscmd(NODE_STATUS_URL)
