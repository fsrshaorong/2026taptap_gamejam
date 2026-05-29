-- 2026 TapTap GameJam 项目
-- 入口文件

function Start()
    log:Write(LOG_INFO, "=== 2026 TapTap GameJam ===")
    log:Write(LOG_INFO, "游戏初始化中...")

    -- 创建场景
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 创建相机
    local cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 5, -10)
    cameraNode:LookAt(Vector3(0, 0, 0))
    local camera = cameraNode:CreateComponent("Camera")

    -- 设置视口
    renderer:SetViewport(0, Viewport:new(scene_, camera))

    log:Write(LOG_INFO, "场景创建完成，准备开始开发！")
end

function Stop()
    log:Write(LOG_INFO, "游戏结束")
end
