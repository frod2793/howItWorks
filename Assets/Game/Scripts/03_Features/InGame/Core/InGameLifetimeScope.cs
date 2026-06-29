using System;
using Cysharp.Threading.Tasks;
using VContainer;
using VContainer.Unity;
using Features.InGame;
using UnityEngine;
using Domain.InGame;
using Features.Settings;

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
            return new IntroViewModel(data, m_skipIntro);
        }, Lifetime.Scoped).As<IIntroViewModel>();

        builder.RegisterComponentInHierarchy<IntroView>();
    }

    private void ConfigureInGame(IContainerBuilder builder)
    {
        builder.Register<GameDataManager>(Lifetime.Singleton).AsImplementedInterfaces();

        builder.Register<DialogueViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<SceneInfoViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<SidePanelViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<DialogueFlowController>(Lifetime.Singleton)
            .WithParameter("startDialogueIndex", m_startDialogueIndex);

        builder.Register<InGameSaveSystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<InGameSoundSystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<InGameInventorySystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<ResourceDomainService>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();

        builder.Register<SettingsViewModel>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<BacklogViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();

        builder.RegisterEntryPoint<InGameOrchestrator>().AsSelf().As<IInGameOrchestrator>();

        builder.RegisterComponentInHierarchy<InGameDialogueView>();
        builder.RegisterComponentInHierarchy<InGameMiniDialogueView>();
        builder.RegisterComponentInHierarchy<InGameDialogueOptionsManager>();
        builder.RegisterComponentInHierarchy<InGameSceneInfoView>();
        builder.RegisterComponentInHierarchy<InGameSidePanelView>();
        builder.RegisterComponentInHierarchy<InGameCharacterView>();
        builder.RegisterComponentInHierarchy<SettingsView>();
        builder.RegisterComponentInHierarchy<BacklogView>();

        builder.Register<SaveLoadModel>(Lifetime.Scoped);
        builder.Register<SaveLoadViewModel>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.RegisterComponentInHierarchy<SaveLoadView>();
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

        if (sceneInfoVM != null && settingsView != null)
        {
            sceneInfoVM.OnRequestSettings += () =>
            {
                settingsView.func_Open();
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
    }
}
#endregion


