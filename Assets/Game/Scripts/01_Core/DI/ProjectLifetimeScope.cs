using UnityEngine;
using VContainer;
using VContainer.Unity;

#region 씬 초기화 (VContainer)
/// <summary>
/// [설명]: 프로젝트 전역에서 유지되는 의존성을 관리하는 LifetimeScope입니다.
/// </summary>
public class ProjectLifetimeScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<SceneLoaderService>(Lifetime.Singleton).AsImplementedInterfaces();

        builder.Register<SoundDataProvider>(Lifetime.Singleton);

        builder.RegisterComponentOnNewGameObject<SoundService>(Lifetime.Singleton, "GlobalSoundService")
            .UnderTransform(this.transform)
            .AsImplementedInterfaces();
    }

    private void Awake()
    {
        DontDestroyOnLoad(gameObject);
    }
}
#endregion
