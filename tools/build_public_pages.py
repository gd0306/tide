#!/usr/bin/env python3
"""Prepare Tide policy/support pages locally. This command never deploys them."""
import argparse
from datetime import date
from html import escape
import json
from pathlib import Path
import sys

try:
    from tools.check_ios_release import ROOT, validate
except ModuleNotFoundError:
    from check_ios_release import ROOT, validate

COPY = {
    "privacy": ("隐私政策", [
        ("适用范围", "本说明适用于潮语 Tide 的个人 API Key（BYOK）版本。此版本默认不提供应用内账户登录、云端学习同步、托管语音或内购服务。"),
        ("保存在设备上的内容", "对话文字、释义、词汇与学习记录、收藏表达和已保存的纠错保存在应用的本机存储中。模型 API Key 独立保存在系统安全存储中，不包含在学习备份中。我们不以潮语服务保存原始麦克风录音。设备系统备份与恢复还受你的系统设置影响。"),
        ("AI 服务的数据处理", "你明确同意并使用 AI 功能时，相关对话文字、选中的句子和必要学习上下文会发送给你选择的模型服务商。原生实时语音会向所选语音服务商发送音频；轮流语音模式在设备支持时使用本机识别，再发送识别文字。AI 纠错、释义和翻译同样涉及所选服务商处理。"),
        ("第三方与 API Key", "个人 Key 模式由设备直接连接所选服务商。服务商按其自己的条款处理请求、记录及计费。请在选择服务商前阅读其数据保留、服务地区与费用说明。切换服务商或自定义请求目的地需要按应用提示重新确认。"),
        ("权限与自愿操作", "麦克风用于你主动开始的口语练习；语音识别权限用于兼容的本机识别模式。文件访问仅用于你主动选择的导入、导出或恢复操作。当前语音练习不拍摄照片或视频。你可以拒绝 AI 处理并继续查看已保存内容。"),
        ("撤回、删除和备份", "你可以在设置中的 AI 处理页面撤回同意，停止后续 AI 请求；已由模型服务商完成的处理无法因此撤销。你可以删除单条对话或全部学习数据，也可以主动导出备份。你导出到其他位置的文件需要自行管理，应用内删除不会自动删除这些副本。"),
        ("收藏和反馈", "收藏与纠错记录仅在你主动保存后保留，不等于语言能力认证。反馈前请检查你要分享的文字，不要提交 API Key、验证码或不必要的个人信息。"),
        ("适用人群与变更", "当前版本面向成年人，并在引导中要求确认年满 18 周岁。后续如增加账户、托管、购买或同步服务，我们会更新说明并在适用时重新征求同意。"),
    ]),
    "support": ("帮助与支持", [
        ("开始第一次练习", "选择学习语言与释义语言，在设置中选择模型服务商并保存自己的 API Key，再按界面说明允许 AI 处理和麦克风权限。不同服务商的文本模型和实时语音能力可能不同。"),
        ("连接或费用问题", "凭据未被接受时，检查服务商、请求地址与 Key 是否匹配；额度或模型权限问题请查看对应服务商控制台。潮语无法修改第三方账户余额。测试或练习可能产生服务商费用，请按自己的账户限制使用。"),
        ("语音与文字", "实时音频是否可用取决于所选服务商、账户权限和设备。部分模型使用本机语音识别、文本生成与系统朗读；设备不支持本机语音时仍可使用文字。来电、耳机切换或网络中断后，请先查看当前会话状态再重试。"),
        ("保护学习数据", "请定期在设置中的学习备份与数据页面导出备份。备份包含对话及学习内容，不包含 Key。升级、排查问题时请勿通过卸载应用清除已有记录。遇到读取故障时先保留原始数据，并使用恢复界面提供的操作。"),
        ("提交问题", "请附上应用版本、系统版本、所选模型服务商、可复现步骤和错误提示。不要发送模型 Key、登录验证码或未经检查的完整学习档案。可通过页面下方的支持邮箱联系运营者，或在公开项目的问题页面提交不含隐私的信息。"),
    ]),
    "terms": ("使用条款", [
        ("服务内容", "潮语 Tide 为成年人提供语言对话练习、翻译、释义、收藏与学习辅助。AI 生成的表达和纠错可能不准确，练习表现是辅助建议，不构成正式语言等级或考试成绩证明。"),
        ("个人模型服务", "当前 BYOK 版本要求你拥有有权使用的服务商账户与 Key，并遵守其适用条款和服务地区要求。模型请求的费用由相应服务商按你的账户计收。请勿分享或使用无权使用的密钥。"),
        ("使用责任", "请合法使用应用，不提交侵犯他人权利的内容，不利用模型生成或传播违法内容。请确认自己有权导入、保存或分享相关文字与档案。AI 生成内容的标识应按应用说明及适用要求保留。"),
        ("数据与反馈", "请阅读隐私政策，了解本地数据和模型请求的区别。你负责保管主动导出的学习备份；反馈时应自行检查其中是否包含个人信息。"),
        ("软件许可与第三方声明", "潮语的开源代码按项目中的 MIT 许可提供，第三方组件仍适用各自许可。应用内保留开源声明。模型服务的许可与费用不包含在开源软件许可中。"),
        ("支持与变更", "我们会根据实际功能更新使用说明。核心服务方式改变时会提供相应提示和适用的同意流程。你的法定权利不因本说明而被排除。"),
    ]),
}

STYLE = """body{margin:0;background:#f5f1e8;color:#262820;font:17px/1.85 system-ui,-apple-system,sans-serif}main{max-width:760px;margin:auto;padding:48px 24px 80px}a{color:#445548;text-underline-offset:4px}nav{display:flex;gap:24px;flex-wrap:wrap;margin:24px 0 40px}h1{font-size:34px;line-height:1.3}h2{font-size:21px;margin-top:36px}p{margin:12px 0}.draft{padding:16px;background:#eee8d9}footer{border-top:1px solid #b8b9ac;margin-top:40px;padding-top:20px;font-size:15px}@media(prefers-color-scheme:dark){body{background:#20221f;color:#eeeadf}a{color:#d6b77a}.draft{background:#3a352a}}"""


def render(kind, config, draft):
    title, sections = COPY[kind]
    owner = config.get("publisher", {}).get("legalName", "").strip()
    email = config.get("publisher", {}).get("supportEmail", "").strip()
    if not draft and (not owner or not email):
        raise ValueError("Publisher identity and support contact are required")
    banner = '<p class="draft">发布预览：运营者、备案及页面信息尚待复核，此文件不可直接作为已完成的发行材料。</p>' if draft else ""
    nav = "".join(f'<a href="../{key}/index.html">{escape(value[0])}</a>' for key, value in COPY.items())
    content = "".join(f"<section><h2>{escape(heading)}</h2><p>{escape(text)}</p></section>" for heading, text in sections)
    footer = f"<p>运营者：{escape(owner or '待配置（仅预览）')}</p><p>支持邮箱：{escape(email or '待配置（仅预览）')}</p>"
    if config.get("appFilingNumber"):
        footer += f'<p>APP 备案：{escape(config["appFilingNumber"])}</p>'
    if kind == "support":
        content += '<p><a href="https://github.com/gd0306/tide/issues">项目问题反馈（公开页面）</a></p>'
    robots = '<meta name="robots" content="noindex">' if draft else ""
    return f'<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">{robots}<title>{title} · 潮语 Tide</title><style>{STYLE}</style></head><body><main>{banner}<p>潮语 Tide</p><h1>{title}</h1><p>更新日期：{date.today().isoformat()}</p><nav aria-label="帮助页面">{nav}</nav>{content}<footer>{footer}</footer></main></body></html>\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "distribution/ios/release-config.json")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/tide-public-pages")
    parser.add_argument("--draft", action="store_true")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        if not isinstance(config, dict):
            raise ValueError("Configuration must be an object")
        # Pages must be built before they can be deployed and checked as live.
        candidate = dict(config)
        candidate["reviewed"] = dict(config.get("reviewed", {}), publicPages=True)
        errors = validate(candidate)
        if errors and not args.draft:
            raise ValueError("Release information is incomplete: " + "; ".join(errors))
        for kind in COPY:
            target = args.output / kind / "index.html"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(render(kind, config, args.draft))
    except (OSError, ValueError, TypeError, AttributeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print("Prepared local pages: " + str(args.output) + "; no deployment performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
