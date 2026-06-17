using VContainer;
using VContainer.Unity;
using Features.InGame;
using UnityEngine;
using Domain.InGame;

#region 씬 초기화 (VContainer)
public class InGameLifetimeScope : LifetimeScope
{

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
            return new IntroViewModel(data);
        }, Lifetime.Scoped).As<IIntroViewModel>();

        builder.RegisterComponentInHierarchy<IntroView>();
    }

    private void ConfigureInGame(IContainerBuilder builder)
    {
        builder.Register<GameDataManager>(Lifetime.Singleton).AsImplementedInterfaces();

        builder.Register<DialogueViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<SceneInfoViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<SidePanelViewModel>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<DialogueFlowController>(Lifetime.Singleton);

        builder.Register<InGameSaveSystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<InGameSoundSystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<InGameInventorySystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<ResourceDomainService>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();

        builder.RegisterEntryPoint<InGameOrchestrator>().AsSelf().As<IInGameOrchestrator>();

        builder.RegisterComponentInHierarchy<InGameDialogueView>();
        builder.RegisterComponentInHierarchy<InGameMiniDialogueView>();
        builder.RegisterComponentInHierarchy<InGameDialogueOptionsManager>();
        builder.RegisterComponentInHierarchy<InGameSceneInfoView>();
        builder.RegisterComponentInHierarchy<InGameSidePanelView>();
        builder.RegisterComponentInHierarchy<InGameCharacterView>();
    }
}
#endregion


