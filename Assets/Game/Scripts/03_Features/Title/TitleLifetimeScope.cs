using VContainer;
using VContainer.Unity;
using UnityEngine;

public class TitleLifetimeScope : LifetimeScope
{
    [SerializeField] private TitleView m_titleView;
    [SerializeField] private PopupView m_popupView;

    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<PopupDataProvider>(Lifetime.Singleton);

        builder.Register<TitleViewModel>(Lifetime.Scoped).AsImplementedInterfaces();
        
        if (m_titleView != null)
        {
            builder.RegisterComponent(m_titleView);
        }

        if (m_popupView != null)
        {
            builder.RegisterComponent(m_popupView);
        }
    }

    private void Start()
    {
        if (Container == null)
        {
            Debug.LogError("[TitleLifetimeScope] VContainer 초기화 미완료");
            return;
        }

        ITitleViewModel titleVMFace = null;
        try
        {
            titleVMFace = Container.Resolve<ITitleViewModel>();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[TitleLifetimeScope] ITitleViewModel 해결 실패: {e.Message}");
            return;
        }

        var titleVM = titleVMFace as TitleViewModel;
        var dataProvider = Container.Resolve<PopupDataProvider>();

        if (m_titleView != null && titleVM != null)
        {
            var soundService = Container.Resolve<ISoundService>();
            m_titleView.Initialize(titleVM, soundService);
            
            if (m_popupView != null && dataProvider != null)
            {
                m_popupView.SetupTestDebug(dataProvider);
            }

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
