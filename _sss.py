#!/usr/bin/env python3
# coding: utf-8
# Create by : https://github.com/lidalao/ServerStatus
# 版本：0.0.1, 支持Python版本：2.7 to 3.9
# 支持操作系统： Linux, OSX, FreeBSD, OpenBSD and NetBSD, both 32-bit and 64-bit architectures

import json
import sys
import os
import requests
import random
import string
import subprocess
import uuid
import secrets  # 新增：用于生成安全随机数

CONFIG_FILE = "config.json"
GITHUB_RAW_URL = "https://raw.githubusercontent.com/bushiwode/ServerStatus/master"
IP_URL = "https://api.ipify.org"

jjs = {}
ip = ""

def how2agent(user, passwd):
    print('```')
    print("\n")
    print(f'curl -L {GITHUB_RAW_URL}/sss-agent.sh  -o sss-agent.sh && chmod +x sss-agent.sh && sudo ./sss-agent.sh {getIP()} {user} {passwd}')
    print("\n")
    print('```')

def getIP():
    global ip
    if ip == "": 
        ip = requests.get(IP_URL).content.decode('utf8')
    return ip

def restartSSS():
    cmd = ["docker-compose", "restart"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    for line in p.stdout:
        print(line)
    p.wait()

def getPasswd():
    # 使用 secrets 模块生成更安全的随机密码
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))

def saveJJs():
    jjs['servers'] = sorted(jjs['servers'], key=lambda d: d['name']) 

    # 使用上下文管理器处理文件
    with open(CONFIG_FILE, "w") as file:
        json.dump(jjs, file)

def _show():
    print("---你的jjs如下---")
    print("\n")
    if len(jjs['servers']) == 0:
        print('>>> 你好MJJ, 暂时没发现你有任何jj! <<<')
        print("\n")
        print("-----------------")
        return
    
    for idx, item in enumerate(jjs['servers']):
        print(f"{idx}. name: {item['name']}, loc: {item['location']}, type: {item['type']}") 
    
    print("\n")
    print("-----------------")

def show():
    _show()
    _back()

def _back():
    print(">>>按任意键返回上级菜单")
    input()
    cmd()

def add():
    print('>>>请输入jj名字：')
    jjname = input()    
    if jjname == "":
        print("输入有误")
        _back()
        return

    print(f'>>>请输入{jjname}位置：[{ "us" }]')
    jjloc = input()
    if jjloc == "":
        jjloc = "us"

    print(f'>>>请输入{jjname}类型：[{ "kvm" }]')
    jjtype = input()
    if jjtype == "":
        jjtype = "kvm"  
     
    item = {}
    item['monthstart'] = "1"
    item['location'] = jjloc
    item['type'] = jjtype
    item['name'] = jjname
    item['username'] = uuid.uuid4().hex
    item['host'] = jjname
    item['password'] = getPasswd()
    jjs['servers'].append(item)
    saveJJs()

    print("操作完成，等待服务重启")
    restartSSS()

    print("添加成功!")
    _show()
    print(f'>>>请复制以下命令在机器{item["name"]}安装agent服务')
    how2agent(item['username'], item['password'])
    _back()

def update():
    print("请输入需要更新的jj标号：")
    idx = input()
    if not idx.isnumeric():
        print('无效输入,退出')
        _back()
        return
    
    if len(jjs['servers']) <= int(idx):
        print('输入无效')
        _back()
        return

    jj = jjs['servers'][int(idx)]
    print(f'--- 面板更换ip时，请复制以下命令在机器{jj["name"]}安装agent服务 ---')
    how2agent(jj['username'], jj['password'])

    print(f'>>>请输入{jj["name"]}新名字：[{jj["name"]}] *中括号内为原值，按回车表示不做修改*')
    jjname = input()
    if "" != jjname:
        jjs['servers'][int(idx)]['name'] = jjname
    
    print(f'>>>请输入{jj["name"]}新位置：[{jj["location"]}]')
    jjloc = input()
    if "" != jjloc:
        jjs['servers'][int(idx)]['location'] = jjloc
    
    print(f'>>>请输入{jj["name"]}新类型：[{jj["type"]}]')
    jjtype = input()
    if "" != jjtype:
        jjs['servers'][int(idx)]['type'] = jjtype
    
    print(f'>>>请输入{jj["name"]}新的月流量起始日：[{jj["monthstart"]}]')
    jjms = input()
    if "" != jjms:
        jjs['servers'][int(idx)]['monthstart'] = jjms

    if "" == jjname and "" == jjloc and "" == jjtype and "" == jjms:
        print('未做任何更新，直接返回')
        _back()
        return
    saveJJs()
    print("操作完成，等待服务重启")
    restartSSS()
    print("更新成功!")
    _show()
    _back()

def remove():
    print(">>>请输入需要删除的jj标号：")
    idx = input()
    if not idx.isnumeric():
        print('无效输入,退出')
        _back()
        return
    
    if len(jjs['servers']) <= int(idx):
        print('输入无效')
        _back()
        return
    
    print(f'>>>请确认你需要删除的节点：{jjs["servers"][int(idx)]["name"]}？ [Y/n]') 
    yesOrNo = input()
    if yesOrNo.lower() == "n":
        print("取消删除")
        _back()
        return

    del jjs['servers'][int(idx)]
    saveJJs()
    print("操作完成，等待服务重启")
    restartSSS()
    print("删除成功!")
    _show()
    _back()
    
def cmd():
    print("\n")
    print('- - - 欢迎使用最简洁的探针: Server Status - - -')
    print('详细教程请参考：https://lidalao.com/archives/87')
    print("\n")
    _show()
    print("\n")

    print('>>>请输入操作标号：1.查看, 2.添加, 3.删除, 4.更新, 0.退出')
    x = input()
    if not x.isnumeric():
        print('无效输入, 退出')
        return
    
    if 1 == int(x):
        show()
    elif 2 == int(x):
        add()
    elif 3 == int(x):
        remove() 
    elif 4 == int(x):
        update()
    elif 0 == int(x):
        return
    else:
        print('无效输入, 退出')
        return

if __name__ == '__main__':
    if not os.path.exists(CONFIG_FILE): 
        print("请在当前目录创建config.json!")
        exit()
    
    # 使用上下文管理器处理文件
    with open(CONFIG_FILE, "r") as file:
        jjs = json.load(file)
    
    cmd()
