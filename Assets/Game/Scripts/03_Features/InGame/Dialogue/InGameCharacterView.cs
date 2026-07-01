using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using VContainer;
using Domain.InGame;
using DG.Tweening;

namespace Features.InGame
{
    public enum IllustrationPlacement
    {
        Left,
        Center,
        Right
    }

    [Serializable]
    public struct CharacterSpriteMap
    {
        public string characterName;
        public Sprite sprite;
        public IllustrationPlacement placement;
    }

    public class InGameCharacterView : MonoBehaviour
    {
        [Header("캐릭터 일러스트 위치 (좌/중/우)")]
        [SerializeField] private Image m_leftCharacterImage;
        [SerializeField] private Image m_centerCharacterImage;
        [SerializeField] private Image m_rightCharacterImage;

        [Header("캐릭터 스프라이트 리소스 데이터 리스트")]
        [SerializeField] private List<CharacterSpriteMap> m_characterSpriteMaps;

        private IDialogueViewModel m_viewModel;

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnDialogueUpdated += UpdateCharacterIllustration;
        }

        private void Start()
        {
            InitImage(m_leftCharacterImage);
            InitImage(m_centerCharacterImage);
            InitImage(m_rightCharacterImage);
        }

        private void UpdateCharacterIllustration(DialogueDTO dialogue)
        {
            if (dialogue.Type == DialogueType.Narration || dialogue.Type == DialogueType.SystemMessage)
            {
                FadeOutImage(m_leftCharacterImage);
                FadeOutImage(m_centerCharacterImage);
                FadeOutImage(m_rightCharacterImage);
                return;
            }

            CharacterSpriteMap matchedMap = default;
            bool isFound = false;

            if (m_characterSpriteMaps != null)
            {
                for (int i = 0; i < m_characterSpriteMaps.Count; i++)
                {
                    if (m_characterSpriteMaps[i].characterName == dialogue.SpeakerName)
                    {
                        matchedMap = m_characterSpriteMaps[i];
                        isFound = true;
                        break;
                    }
                }
            }

            if (!isFound)
            {
                FadeOutImage(m_leftCharacterImage);
                FadeOutImage(m_centerCharacterImage);
                FadeOutImage(m_rightCharacterImage);
                return;
            }

            if (matchedMap.placement == IllustrationPlacement.Left)
            {
                FadeInImage(m_leftCharacterImage, matchedMap.sprite);
                FadeOutImage(m_centerCharacterImage);
                FadeOutImage(m_rightCharacterImage);
            }
            else if (matchedMap.placement == IllustrationPlacement.Center)
            {
                FadeInImage(m_centerCharacterImage, matchedMap.sprite);
                FadeOutImage(m_leftCharacterImage);
                FadeOutImage(m_rightCharacterImage);
            }
            else
            {
                FadeInImage(m_rightCharacterImage, matchedMap.sprite);
                FadeOutImage(m_leftCharacterImage);
                FadeOutImage(m_centerCharacterImage);
            }
        }

        private void InitImage(Image image)
        {
            if (image != null)
            {
                Color c = image.color;
                c.a = 0f;
                image.color = c;
                image.gameObject.SetActive(false);
            }
        }

        private void FadeInImage(Image image, Sprite sprite)
        {
            if (image != null)
            {
                image.sprite = sprite;
                image.gameObject.SetActive(true);
                image.DOKill();
                image.DOFade(1f, 0.3f);
            }
        }

        private void FadeOutImage(Image image)
        {
            if (image != null)
            {
                image.DOKill();
                image.DOFade(0f, 0.3f).OnComplete(() =>
                {
                    image.gameObject.SetActive(false);
                });
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDialogueUpdated -= UpdateCharacterIllustration;
            }
        }
    }
}
