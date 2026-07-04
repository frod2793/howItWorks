using System;
using System.Collections.Generic;
using Cysharp.Threading.Tasks;
using Domain.InGame;
using Features.InGame;
using Features.Settings;
using UnityEngine;
using VContainer;
using VContainer.Unity;

#region 씬 초기화 (VContainer)
public class InGameLifetimeScope : LifetimeScope
{
    [Header("테스트 설정")]
    [SerializeField] private int m_startDialogueIndex = 0;
    [SerializeField] private bool m_skipIntro = true;

    protected override void Configure(IContainerBuilder builder)
    {
        ConfigureIntro(builder);
        ConfigureInGame(builder);
    }

    private void ConfigureIntro(IContainerBuilder builder)
    {
        builder.Register<IntroDataProvider>(Lifetime.Singleton);

        builder.Register(container =>
        {
            var provider = container.Resolve<IntroDataProvider>();
            var data = provider.LoadIntroData();
            var soundService = container.Resolve<ISoundService>();
            return new IntroViewModel(data, m_skipIntro, soundService);
        }, Lifetime.Scoped).As<IIntroViewModel>();

        RegisterComponentSafe<IntroView>(builder);
    }

    private void ConfigureInGame(IContainerBuilder builder)
    {
        builder.Register<GameDataManager>(Lifetime.Singleton).AsImplementedInterfaces();

        builder.Register<DialogueViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<SceneInfoViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<SidePanelViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<SystemMenuViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.RegisterEntryPoint<UIStackService>();
        builder.Register<DialogueFlowController>(Lifetime.Singleton)
            .WithParameter("startDialogueIndex", m_startDialogueIndex);

        builder.Register<InGameSaveSystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<InGameSoundSystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<InGameInventorySystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<ResourceDomainService>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();

        builder.Register<SettingsViewModel>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<BacklogViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();

        builder.RegisterEntryPoint<InGameOrchestrator>().AsSelf().As<IInGameOrchestrator>();

        RegisterComponentSafe<InGameDialogueView>(builder);
        RegisterComponentSafe<InGameDialogueOptionsManager>(builder);
        RegisterComponentSafe<InGameSceneInfoView>(builder);
        RegisterComponentSafe<InGameSidePanelView>(builder);
        RegisterComponentSafe<InGameCharacterView>(builder);
        RegisterComponentSafe<SettingsView>(builder);
        RegisterComponentSafe<BacklogView>(builder);
        RegisterComponentSafe<InGameInventoryView>(builder);
        builder.Register<InGameEncyclopediaViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        RegisterComponentSafe<InGameEncyclopediaView>(builder);
        RegisterComponentSafe<SystemMenuView>(builder);

        builder.Register<SaveLoadModel>(Lifetime.Scoped);
        builder.Register<SaveLoadViewModel>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        RegisterComponentSafe<SaveLoadView>(builder);
    }

    private void Start()
    {
        if (Container == null)
        {
            return;
        }

        ISettingsViewModel settingsVM = null;
        try
        {
            settingsVM = Container.Resolve<ISettingsViewModel>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] ISettingsViewModel 해결 실패: {e.Message}");
        }

        var settingsView = Container.Resolve<SettingsView>();
        if (settingsView != null && settingsVM != null)
        {
            settingsView.Initialize(settingsVM);
        }

        ISceneInfoViewModel sceneInfoVM = null;
        try
        {
            sceneInfoVM = Container.Resolve<ISceneInfoViewModel>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] ISceneInfoViewModel 해결 실패: {e.Message}");
        }

        SystemMenuView systemMenuView = null;
        try
        {
            systemMenuView = Container.Resolve<SystemMenuView>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] SystemMenuView 해결 실패: {e.Message}");
        }

        ISystemMenuViewModel systemMenuVM = null;
        try
        {
            systemMenuVM = Container.Resolve<ISystemMenuViewModel>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] ISystemMenuViewModel 해결 실패: {e.Message}");
        }

        ISoundService soundService = null;
        try
        {
            soundService = Container.Resolve<ISoundService>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] ISoundService 해결 실패: {e.Message}");
        }

        if (systemMenuView != null && systemMenuVM != null && soundService != null)
        {
            systemMenuView.Initialize(systemMenuVM, soundService);
        }

        if (sceneInfoVM != null && systemMenuView != null)
        {
            sceneInfoVM.OnRequestSettings += () =>
            {
                systemMenuView.func_Open();
            };

            if (systemMenuVM != null)
            {
                sceneInfoVM.OnSceneInfoChanged += (info) =>
                {
                    systemMenuVM.SetSceneInfo(info);
                };
            }
        }

        SaveLoadView saveLoadView = null;
        try
        {
            saveLoadView = Container.Resolve<SaveLoadView>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] SaveLoadView 해결 실패: {e.Message}");
        }

        ISaveLoadViewModel saveLoadVM = null;
        try
        {
            saveLoadVM = Container.Resolve<ISaveLoadViewModel>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] ISaveLoadViewModel 해결 실패: {e.Message}");
        }

        if (saveLoadView != null && saveLoadVM != null)
        {
            saveLoadView.Initialize(saveLoadVM);
        }

        InGameEncyclopediaView encyclopediaView = null;
        try
        {
            encyclopediaView = Container.Resolve<InGameEncyclopediaView>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] InGameEncyclopediaView 해결 실패: {e.Message}");
        }

        if (systemMenuVM != null)
        {
            systemMenuVM.OnResumeRequested += () =>
            {
                if (systemMenuView != null)
                {
                    systemMenuView.func_Close();
                }
            };
            systemMenuVM.OnSaveLoadRequested += () =>
            {
                if (saveLoadView != null)
                {
                    saveLoadView.func_Open(true);
                }
            };
            systemMenuVM.OnSettingsRequested += () =>
            {
                if (settingsView != null)
                {
                    settingsView.func_Open();
                }
            };
            systemMenuVM.OnEncyclopediaRequested += () =>
            {
                if (encyclopediaView != null)
                {
                    encyclopediaView.func_Open();
                }
            };
            systemMenuVM.OnTitleRequested += () =>
            {
                try
                {
                    var sceneLoader = Container.Resolve<ISceneLoader>();
                    if (sceneLoader != null)
                    {
                        sceneLoader.LoadScene("Title", 0.5f);
                    }
                }
                catch (Exception ex)
                {
                    Debug.LogError($"[InGameLifetimeScope] 타이틀 씬 로드 시도 실패: {ex.Message}");
                }
            };
            systemMenuVM.OnExitRequested += () =>
            {
                Debug.Log("[InGameLifetimeScope] 게임 종료가 요청되었습니다.");
                Application.Quit();
            };
        }

        IBacklogViewModel backlogVM = null;
        try
        {
            backlogVM = Container.Resolve<IBacklogViewModel>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] IBacklogViewModel 해결 실패: {e.Message}");
        }

        var backlogView = Container.Resolve<BacklogView>();
        if (backlogView != null && backlogVM != null)
        {
            backlogView.Initialize(backlogVM);
        }

        IDialogueViewModel dialogueVM = null;
        try
        {
            dialogueVM = Container.Resolve<IDialogueViewModel>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] IDialogueViewModel 해결 실패: {e.Message}");
        }

        if (dialogueVM != null && backlogView != null)
        {
            dialogueVM.OnRequestBacklog += () =>
            {
                backlogView.func_Open();
            };
        }

        IIntroViewModel introVM = null;
        try
        {
            introVM = Container.Resolve<IIntroViewModel>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] IIntroViewModel 해결 실패: {e.Message}");
        }

        DialogueFlowController dialogueFlowController = null;
        try
        {
            dialogueFlowController = Container.Resolve<DialogueFlowController>();
        }
        catch (Exception e)
        {
            Debug.LogError($"[InGameLifetimeScope] DialogueFlowController 해결 실패: {e.Message}");
        }

        if (introVM != null && dialogueFlowController != null)
        {
            introVM.OnIntroFinished += () =>
            {
                dialogueFlowController.StartDialogueFlowAsync().Forget();
            };
        }

        InGameInventoryView inventoryView = null;
        IInGameInventorySystem inventorySystem = null;
        try
        {
            inventoryView = Container.Resolve<InGameInventoryView>();
            inventorySystem = Container.Resolve<IInGameInventorySystem>();
        }
        catch (Exception)
        {
            Debug.LogWarning("[InGameLifetimeScope] 인벤토리 시스템 또는 뷰 객체 초기화가 생략되었습니다. (독립 씬 실행 상태 시 정상)");
        }

        if (inventoryView != null && inventorySystem != null)
        {
            inventoryView.Initialize(inventorySystem, "SCN_03_PLAZA");
        }

        IInGameSaveSystem saveSystem = null;
        try
        {
            saveSystem = Container.Resolve<IInGameSaveSystem>();
        }
        catch (Exception)
        {
            Debug.LogWarning("[InGameLifetimeScope] 저장 시스템 객체 초기화가 생략되었습니다. (독립 씬 실행 상태 시 정상)");
        }

        if (encyclopediaView != null)
        {
            List<string> unlockedEndings = new List<string>();
            if (saveSystem != null)
            {
                var globalData = saveSystem.LoadGlobalProgress();
                if (globalData != null && globalData.unlockedEndings != null)
                {
                    unlockedEndings = globalData.unlockedEndings;
                }
            }
            encyclopediaView.Initialize(unlockedEndings);
        }
    }

    private void RegisterComponentSafe<T>(IContainerBuilder builder) where T : MonoBehaviour
    {
        T component = UnityEngine.Object.FindAnyObjectByType<T>(UnityEngine.FindObjectsInactive.Include);
        if (component != null)
        {
            builder.RegisterComponent(component);
        }
        else
        {
            Debug.LogWarning($"[InGameLifetimeScope] 씬 하이어라키에서 {typeof(T).Name} 컴포넌트를 찾을 수 없어 VContainer 등록을 생략합니다.");
        }
    }

    protected override void OnDestroy()
    {
        try
        {
            if (Container != null)
            {
                var uiStack = Container.Resolve<IUIStackService>();
                if (uiStack != null)
                {
                    uiStack.Clear();
                }
            }
        }
        catch (Exception)
        {
            // 컨테이너 파괴 과정 중의 의존성 오류 무시
        }
        base.OnDestroy();
    }
}
#endregion

