using VContainer;
using VContainer.Unity;
using UnityEngine;
using Features.Settings;

public class TitleLifetimeScope : LifetimeScope
{
    [SerializeField] private TitleView m_titleView;
    [SerializeField] private PopupView m_popupView;
    [SerializeField] private SettingsView m_settingsView;

    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<PopupDataProvider>(Lifetime.Singleton);

        builder.Register<TitleViewModel>(Lifetime.Scoped).AsImplementedInterfaces();
        builder.Register<SettingsViewModel>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        
        if (m_titleView != null)
        {
            builder.RegisterComponent(m_titleView);
        }

        if (m_popupView != null)
        {
            builder.RegisterComponent(m_popupView);
        }

        if (m_settingsView != null)
        {
            builder.RegisterComponent(m_settingsView);
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

        ISettingsViewModel settingsVMFace = null;
        try
        {
            settingsVMFace = Container.Resolve<ISettingsViewModel>();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[TitleLifetimeScope] ISettingsViewModel 해결 실패: {e.Message}");
        }

        var settingsVM = settingsVMFace as SettingsViewModel;
        if (m_settingsView != null && settingsVM != null)
        {
            m_settingsView.Initialize(settingsVM);
            settingsVM.OnCloseRequested += () =>
            {
                if (m_titleView != null)
                {
                    m_titleView.gameObject.SetActive(true);
                }
            };
        }

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

            titleVM.OnRequestSettings += () =>
            {
                if (m_settingsView != null)
                {
                    m_settingsView.func_Open();
                    if (m_titleView != null)
                    {
                        m_titleView.gameObject.SetActive(false);
                    }
                }
            };
        }
    }
}
