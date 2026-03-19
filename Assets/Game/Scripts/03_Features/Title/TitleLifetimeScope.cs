using VContainer;
using VContainer.Unity;
using UnityEngine;

#region 씬 초기화 (VContainer)
/// <summary>
/// [설명]: 타이틀 씬의 의존성 주입을 담당하는 LifetimeScope입니다.
/// </summary>
public class TitleLifetimeScope : LifetimeScope
{
    #region 에디터 설정
    [SerializeField] private TitleView m_titleView;
    [SerializeField] private PopupView m_popupView;
    #endregion

    protected override void Configure(IContainerBuilder builder)
    {
        // Data Provider 등록
        builder.Register<PopupDataProvider>(Lifetime.Singleton);

        // ViewModel 등록
        builder.Register<TitleViewModel>(Lifetime.Scoped).AsImplementedInterfaces();
        
        // View 인스턴스 주입 (인스펙터에 할당된 경우에만)
        if (m_titleView != null) builder.RegisterComponent(m_titleView);
        if (m_popupView != null) builder.RegisterComponent(m_popupView);
    }

    private void Start()
    {
        if (Container == null)
        {
            Debug.LogError("[TitleLifetimeScope] VContainer가 아직 초기화되지 않았습니다. 인스펙터 설정을 확인해 주세요.");
            return;
        }

        ITitleViewModel titleVMFace = null;
        try
        {
            titleVMFace = Container.Resolve<ITitleViewModel>();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[TitleLifetimeScope] ITitleViewModel 해결 실패: {e.Message}\n프로젝트 설정에서 ProjectLifetimeScope 프리팹이 등록되어 있는지 확인하십시오.");
            return;
        }

        var titleVM = titleVMFace as TitleViewModel;
        var dataProvider = Container.Resolve<PopupDataProvider>();

        if (m_titleView != null && titleVM != null)
        {
            var soundService = Container.Resolve<ISoundService>();
            m_titleView.Initialize(titleVM, soundService);
            
            // 팝업 테스트 기능 설정 (디버그용)
            if (m_popupView != null && dataProvider != null)
            {
                m_popupView.SetupTestDebug(dataProvider);
            }

            // 팝업 이벤트 연결 (데이터 제공자를 통해 키 기반 데이터 조회)
            titleVM.OnRequestPopup += key => 
            {
                if (m_popupView != null && dataProvider != null)
                {
                    var data = dataProvider.GetPopupData(key);
                    var popupVM = new PopupViewModel(data.Message, data.Subtitle, data.AnimationKey);
                    m_popupView.Initialize(popupVM);
                }
            };
        }
    }
}
#endregion
