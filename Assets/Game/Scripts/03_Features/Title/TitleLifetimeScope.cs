using VContainer;
using VContainer.Unity;
using UnityEngine;
using Features.Settings;
using Features.InGame;
using Domain.InGame;

public class TitleLifetimeScope : LifetimeScope
{
    [SerializeField] private TitleView m_titleView;
    [SerializeField] private PopupView m_popupView;
    [SerializeField] private SettingsView m_settingsView;
    [SerializeField] private GlobalProgressView m_globalProgressView;

    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<PopupDataProvider>(Lifetime.Singleton);
        builder.Register<InGameSaveSystem>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<TitleViewModel>(Lifetime.Scoped).AsImplementedInterfaces();
        builder.Register<SettingsViewModel>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.Register<GlobalProgressViewModel>(Lifetime.Scoped);
        builder.Register<SaveLoadModel>(Lifetime.Scoped);
        builder.Register<SaveLoadViewModel>(Lifetime.Scoped).AsImplementedInterfaces().AsSelf();
        builder.RegisterComponentInHierarchy<SaveLoadView>();

        builder.Register(c =>
        {
            var saveSystem = c.Resolve<IInGameSaveSystem>();
            var globalData = saveSystem.LoadGlobalProgress();
            var progressDTO = new GlobalProgressDTO();
            if (globalData != null)
            {
                progressDTO.PlayCount = globalData.playthroughCount > 0 ? globalData.playthroughCount : 1;
                progressDTO.UnlockedEndings = globalData.unlockedEndings != null ? globalData.unlockedEndings.Count : 0;
                progressDTO.TotalEndings = 9;
                progressDTO.AccumulatedTime = globalData.totalPlayTimeSeconds;
                progressDTO.ArchiveCount = globalData.archiveCount;
                
                var saveData = saveSystem.LoadSessionData(0);
                if (saveData != null)
                {
                    progressDTO.SubplotCount = saveData.subplotProgress != null ? saveData.subplotProgress.Count : 0;
                }
                progressDTO.TotalSubplots = 5;
                progressDTO.TotalArchives = 19;
            }
            return new GlobalProgressModel(progressDTO);
        }, Lifetime.Scoped);
        
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

        if (m_globalProgressView != null)
        {
            builder.RegisterComponent(m_globalProgressView);
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

        SaveLoadView saveLoadView = null;
        try
        {
            saveLoadView = Container.Resolve<SaveLoadView>();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[TitleLifetimeScope] SaveLoadView 해결 실패: {e.Message}");
        }

        ISaveLoadViewModel saveLoadVMFace = null;
        try
        {
            saveLoadVMFace = Container.Resolve<ISaveLoadViewModel>();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[TitleLifetimeScope] ISaveLoadViewModel 해결 실패: {e.Message}");
        }

        var saveLoadVM = saveLoadVMFace as SaveLoadViewModel;
        if (saveLoadView != null && saveLoadVM != null)
        {
            saveLoadView.Initialize(saveLoadVM);
            saveLoadVM.OnCloseRequested += () =>
            {
                if (m_titleView != null)
                {
                    m_titleView.gameObject.SetActive(true);
                }
            };
        }

        GlobalProgressViewModel progressVM = null;
        try
        {
            progressVM = Container.Resolve<GlobalProgressViewModel>();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[TitleLifetimeScope] GlobalProgressViewModel 해결 실패: {e.Message}");
        }

        if (m_titleView != null && titleVM != null)
        {
            var soundService = Container.Resolve<ISoundService>();
            m_titleView.Initialize(titleVM, soundService);

            if (m_globalProgressView != null && progressVM != null)
            {
                m_globalProgressView.Initialize(progressVM);
            }

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

            titleVM.OnRequestSaveLoad += () =>
            {
                if (saveLoadView != null)
                {
                    saveLoadView.func_Open(false);
                    if (m_titleView != null)
                    {
                        m_titleView.gameObject.SetActive(false);
                    }
                }
            };
        }
    }
}
