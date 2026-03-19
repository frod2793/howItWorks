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
        // 씬 로더 서비스 등록 (전역 싱글톤)
        builder.Register<SceneLoaderService>(Lifetime.Singleton).AsImplementedInterfaces();

        // 사운드 데이터 프로바이더 등록
        builder.Register<SoundDataProvider>(Lifetime.Singleton);

        // 사운드 서비스 등록 (신규 게임 오브젝트로 생성하여 전역 유지)
        builder.RegisterComponentOnNewGameObject<SoundService>(Lifetime.Singleton, "GlobalSoundService")
            .UnderTransform(this.transform)
            .AsImplementedInterfaces();
    }

    private void Awake()
    {
        // 이 LifetimeScope는 씬이 바뀌어도 파괴되지 않도록 설정
        DontDestroyOnLoad(gameObject);
    }
}
#endregion
