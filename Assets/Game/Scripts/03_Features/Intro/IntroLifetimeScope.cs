using VContainer;
using VContainer.Unity;
using UnityEngine;

#region 씬 초기화 (VContainer)
/// <summary>
/// [설명]: 인트로 씬의 의존성 주입 및 자동 시작을 담당하는 LifetimeScope입니다.
/// </summary>
public class IntroLifetimeScope : LifetimeScope
{
    #region 에디터 설정
    [SerializeField] private IntroView m_introView;
    #endregion

    protected override void Configure(IContainerBuilder builder)
    {
        // Data Provider 등록
        builder.Register<IntroDataProvider>(Lifetime.Singleton);

        // ViewModel 등록 (데이터 로드 포함)
        builder.Register(container =>
        {
            var provider = container.Resolve<IntroDataProvider>();
            var data = provider.LoadIntroData();
            return new IntroViewModel(data);
        }, Lifetime.Scoped).AsImplementedInterfaces().AsSelf();

        // View 인스턴스 주입
        if (m_introView != null)
        {
            builder.RegisterComponent(m_introView);
        }
    }

    private void Start()
    {
        if (Container == null)
        {
            Debug.LogError("[IntroLifetimeScope] VContainer가 아직 초기화되지 않았습니다.");
            return;
        }

        // 인트로 자동 시작을 위해 씬 진입 시 초기화 수행
        try 
        {
            var introVM = Container.Resolve<IIntroViewModel>();
            var sceneLoader = Container.Resolve<ISceneLoader>();
            var soundService = Container.Resolve<ISoundService>();
            
            if (m_introView != null && introVM != null)
            {
                m_introView.Setup(introVM.TypingSpeed);
                m_introView.Initialize(introVM, sceneLoader, soundService);
            }
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[IntroLifetimeScope] 의존성 해결 실패: {e.Message}\n프로젝트 설정(VContainer Project Settings)을 확인하십시오.");
        }
    }
}
#endregion
