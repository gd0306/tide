# 中国大陆 iOS 首发准备

本配置针对个人开发者、仅中国大陆首发、BYOK、账户/托管/内购默认关闭的潮语版本。它不包含个人签名、凭据或真实备案材料；通过结构检查不代表获得监管或 Apple 批准。

公开页面采用用户选定的地址：

- `https://gd306.cn/tide/privacy/`
- `https://gd306.cn/tide/support/`
- `https://gd306.cn/tide/terms/`

## 编辑配置

`release-config.json` 是可提交的空主体开发配置。可复制到 Git 忽略的 `distribution/private/ios-release.json` 后填写正式资料，避免误提交私人材料。模型授权协议正文和签名材料不要存入配置或源码，只记录可公开的引用地址。

需由运营者核实并填写：法定姓名、公开支持邮箱、APP 备案号、实际启用的模型名称/备案信息和使用授权，以及隐私/标识/授权复核结果。`reviewed.publicPages` 只在页面实际发布并核对内容后设为 true，不能因为本地生成了页面就设为 true。

```sh
# 生成草稿页面用于本地审阅，不部署
python3 tools/build_public_pages.py --draft

# 完整配置可生成待发布页面，不会访问或修改服务器
python3 tools/build_public_pages.py --config distribution/private/ios-release.json

# 将有意公开的资料同步到两个客户端；不包含授权内部资料
python3 tools/generate_public_information.py --config distribution/private/ios-release.json
python3 tools/generate_project.py

# 正式发行前执行；缺失主体、备案、授权、真实页面或复核项应失败
python3 tools/check_ios_release.py --config distribution/private/ios-release.json
```

页面输出到 `.build/tide-public-pages/`，包含 `privacy/index.html`、`support/index.html` 和 `terms/index.html`，对应域名的 `/tide/` 目录。`--draft` 会增加禁止索引和未完成提示，草稿不能作为最终发布材料。

`PublicInformation.json` / Android `raw/public_information.json` 仅包含公开主体、支持地址、页面地址、备案号和服务名称。默认 `publicPagesReady=false`，客户端提供本地说明而不打开尚未确认发布的外部页面。若采用私有配置生成资源，公开的元数据会进入安装包；提交前应再次确认这是你希望公开的内容。

## 仍需人工或外部核对的事项

- APP 备案、AI 服务相关受理及个人主体适用条件；有业务前置审批要求时先办理。
- 模型实际服务地区、授权、内容标识与隐私数据处理；不能凭用户自带 Key 推定豁免。
- 部署页面并实测上述 URL，确认内容与实际发行功能一致。
- App Store Connect 的应用记录、地区、年龄分级、隐私标签、截图、审核体验和发行签名。
- 真机语音、耳机路由、权限拒绝、弱网、后台与长时间使用测试。

普通 Debug 构建不运行正式发行门禁，仍可使用合成数据测试和本地学习功能。配置检查是离线结构验证，不会验证政府备案真伪、合同有效性或网页在线状态。

本次代码改造不部署 `gd306.cn` 或任何服务；源码构建不会改变现有线上站点。
