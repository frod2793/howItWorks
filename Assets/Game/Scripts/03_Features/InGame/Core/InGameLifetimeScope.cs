using VContainer;
using VContainer.Unity;
using Features.InGame;
using UnityEngine;

#region 씬 초기화 (VContainer)
public class InGameLifetimeScope : LifetimeScope
{
    #region 에디터 설정

    #endregion

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

        builder.RegisterEntryPoint<InGameInputController>();

        builder.RegisterComponentInHierarchy<InGameDialogueView>();
        builder.RegisterComponentOnNewGameObject<InGameMiniDialogueView>(Lifetime.Scoped, "MiniDialoguePanel");
        builder.RegisterComponentOnNewGameObject<InGameDialogueOptionsGroupView>(Lifetime.Scoped, "DialogueOptionsGroup");
        builder.RegisterComponentInHierarchy<InGameSceneInfoView>();
        builder.RegisterComponentInHierarchy<InGameSidePanelView>();
    }
}
#endregion
